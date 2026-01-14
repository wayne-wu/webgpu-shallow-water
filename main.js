import Stats from 'https://unpkg.com/three@0.160.0/examples/jsm/libs/stats.module.js';

const eyeCoordinate = { radius: 3.5, phi: 0.8, theta: 0.8 };
const lightPos = [ 0.0, 3.0, 0.0 ];
const HEIGHT_RES = 512;
const CAUSTICS_SIZE = 512;
const BOUNDS = 2.0;
const BOUNDS_HALF = BOUNDS * 0.5;

const effectController = {
    mousePos: { x: 0, y: 0 },
    mouseSpeed: { x: 0, y: 0 },
    mouseDeep: 0.3,
    mouseSize: 0.12,
    viscosity: 0.995,
    speed: 10,
    causticsEnabled: true,
    causticsDebug: false,
    causticsBlurEnabled: true,
    causticsThreshold: 0.2,
    causticsGain: 0.3
};

let canvas;
let device;
let context;
let canvasFormat;
let maxTextureSize = 8192;
let heightPipeline;
let copyPipeline;
let causticsPipeline;
let blurPipeline;
let renderPipeline;
let heightUniformBuffer;
let copyUniformBuffer;
let causticsUniformBuffer;
let blurUniformBuffer;
let renderUniformBuffer;
let heightBindGroup;
let copyBindGroup;
let causticsBindGroup;
let blurBindGroupH;
let blurBindGroupV;
let renderBindGroup;
let heightBuffer0;
let heightBuffer1;
let causticsTexture;
let causticsBlurTexture;
let linearSampler;
let quadBuffer;
let lightWaveBuffer;
let lightWaveVertexCount = 0;
let lastX = 0;
let lastY = 0;
const mouseCoords = { x: 0, y: 0 };
let stats;
let resetHeightData;
let mouseDown = false;
let firstClick = true;
let updateOriginMouseDown = false;
let controlsEnabled = true;
let mouseX = 0;
let mouseY = 0;
let gui;

const startTime = performance.now();

function createLightWaveVertices( width = 256, height = 256 ) {

    const verts = [];
    for ( let i = 0; i < height; i ++ ) {
        for ( let j = 0; j < width; j ++ ) {
            const v1x = ( i / height ) * 2 - 1;
            const v1y = ( j / width ) * 2 - 1;
            const v2x = ( ( i + 1 ) / height ) * 2 - 1;
            const v2y = ( ( j + 1 ) / width ) * 2 - 1;
            verts.push( v1x, v1y, v1x, v2y, v2x, v2y );
            verts.push( v1x, v1y, v2x, v2y, v2x, v1y );
        }
    }

    return new Float32Array( verts );

}

function getCartesian( coord ) {

    const radius = coord.radius;
    const phi = coord.phi;
    const theta = coord.theta;
    return {
        x: radius * Math.sin( phi ) * Math.cos( theta ),
        y: radius * Math.cos( phi ),
        z: radius * Math.sin( phi ) * Math.sin( theta )
    };

}

function normalize( v ) {

    const len = Math.hypot( v.x, v.y, v.z );
    if ( len === 0 ) return { x: 0, y: 0, z: 0 };
    return { x: v.x / len, y: v.y / len, z: v.z / len };

}

function subtract( a, b ) {

    return { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z };

}

function add( a, b ) {

    return { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z };

}

function multiplyScalar( v, s ) {

    return { x: v.x * s, y: v.y * s, z: v.z * s };

}

function cross( a, b ) {

    return {
        x: a.y * b.z - a.z * b.y,
        y: a.z * b.x - a.x * b.z,
        z: a.x * b.y - a.y * b.x
    };

}

function getRightVector( coord ) {

    return { x: Math.sin( coord.theta ), y: 0, z: - Math.cos( coord.theta ) };

}

function setMouseCoords( x, y ) {

    const width = canvas.clientWidth || window.innerWidth;
    const height = canvas.clientHeight || window.innerHeight;
    mouseCoords.x = ( x / width ) * 2 - 1;
    mouseCoords.y = - ( y / height ) * 2 + 1;

}

function getRayDirection( screen ) {

    const eye = getCartesian( eyeCoordinate );
    const focus = { x: 0, y: 0, z: 0 };
    const forward = normalize( subtract( focus, eye ) );
    let right = normalize( getRightVector( eyeCoordinate ) );
    const up = normalize( cross( right, forward ) );

    const ar = screen.width / screen.height;
    right = multiplyScalar( right, ar );

    const imagePos = add(
        add( add( eye, multiplyScalar( right, mouseCoords.x ) ), multiplyScalar( up, mouseCoords.y ) ),
        multiplyScalar( forward, 2.0 )
    );
    return normalize( subtract( imagePos, eye ) );

}

function raycast( screen ) {

    if ( mouseDown && ( firstClick || ! controlsEnabled ) ) {

        const eye = getCartesian( eyeCoordinate );
        const dir = getRayDirection( screen );
        const t = - eye.y / dir.y;
        const hit = add( eye, multiplyScalar( dir, t ) );
        const inBounds = Math.max( Math.abs( hit.x ), Math.abs( hit.z ) ) <= BOUNDS_HALF;

        if ( inBounds ) {

            let deltaX = hit.x - effectController.mousePos.x;
            let deltaY = hit.z - effectController.mousePos.y;

            if ( updateOriginMouseDown ) {
                effectController.mousePos.x = hit.x;
                effectController.mousePos.y = hit.z;
                deltaX = 0.05;
                deltaY = 0.0;
                updateOriginMouseDown = false;
            }

            effectController.mouseSpeed.x = deltaX;
            effectController.mouseSpeed.y = deltaY;
            effectController.mousePos.x = hit.x;
            effectController.mousePos.y = hit.z;

            if ( firstClick ) {
                controlsEnabled = false;
            }

        } else {

            updateOriginMouseDown = true;
            effectController.mouseSpeed.x = 0;
            effectController.mouseSpeed.y = 0;

        }

        firstClick = false;

    } else {

        updateOriginMouseDown = true;
        effectController.mouseSpeed.x = 0;
        effectController.mouseSpeed.y = 0;

    }

}

function resizeCanvas() {

    const devicePixelRatio = window.devicePixelRatio || 1;
    const cssWidth = canvas.clientWidth || window.innerWidth;
    const cssHeight = canvas.clientHeight || window.innerHeight;
    const targetWidth = cssWidth * devicePixelRatio;
    const targetHeight = cssHeight * devicePixelRatio;
    const scale = Math.min(
        maxTextureSize / targetWidth,
        maxTextureSize / targetHeight,
        1
    );
    const width = Math.floor( targetWidth * scale );
    const height = Math.floor( targetHeight * scale );
    if ( canvas.width !== width || canvas.height !== height ) {
        canvas.width = width;
        canvas.height = height;
    }
    context.configure( {
        device,
        format: canvasFormat,
        usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_DST,
        alphaMode: 'opaque'
    } );
    return { width, height };

}

function updateUniforms( screen ) {

    const time = ( performance.now() - startTime ) / 1000;
    const renderArray = new Float32Array( 16 );
    renderArray[ 0 ] = screen.width;
    renderArray[ 1 ] = screen.height;
    renderArray[ 2 ] = time;
    renderArray[ 3 ] = 0.0;
    renderArray[ 4 ] = HEIGHT_RES;
    renderArray[ 5 ] = HEIGHT_RES;
    renderArray[ 6 ] = effectController.causticsEnabled ? 1.0 : 0.0;
    renderArray[ 7 ] = effectController.causticsDebug ? 1.0 : 0.0;
    renderArray[ 8 ] = eyeCoordinate.radius;
    renderArray[ 9 ] = eyeCoordinate.phi;
    renderArray[ 10 ] = eyeCoordinate.theta;
    renderArray[ 11 ] = 0.0;
    renderArray[ 12 ] = lightPos[ 0 ];
    renderArray[ 13 ] = lightPos[ 1 ];
    renderArray[ 14 ] = lightPos[ 2 ];
    renderArray[ 15 ] = 0.0;
    device.queue.writeBuffer( renderUniformBuffer, 0, renderArray.buffer );

    const heightArray = new Float32Array( 8 );
    heightArray[ 0 ] = HEIGHT_RES;
    heightArray[ 1 ] = HEIGHT_RES;
    heightArray[ 2 ] = effectController.mousePos.x;
    heightArray[ 3 ] = effectController.mousePos.y;
    heightArray[ 4 ] = Math.hypot( effectController.mouseSpeed.x, effectController.mouseSpeed.y );
    heightArray[ 5 ] = effectController.mouseSize;
    heightArray[ 6 ] = effectController.mouseDeep;
    heightArray[ 7 ] = effectController.viscosity;
    device.queue.writeBuffer( heightUniformBuffer, 0, heightArray.buffer );

    const copyArray = new Float32Array( [ HEIGHT_RES, HEIGHT_RES, 0, 0 ] );
    device.queue.writeBuffer( copyUniformBuffer, 0, copyArray.buffer );

    const causticsArray = new Float32Array( 16 );
    causticsArray[ 0 ] = time;
    causticsArray[ 1 ] = HEIGHT_RES;
    causticsArray[ 2 ] = HEIGHT_RES;
    causticsArray[ 3 ] = CAUSTICS_SIZE;
    causticsArray[ 4 ] = CAUSTICS_SIZE;
    causticsArray[ 5 ] = lightPos[ 0 ];
    causticsArray[ 6 ] = lightPos[ 1 ];
    causticsArray[ 7 ] = lightPos[ 2 ];
    causticsArray[ 8 ] = lightPos[ 0 ];
    causticsArray[ 9 ] = lightPos[ 1 ];
    causticsArray[ 10 ] = lightPos[ 2 ];
    causticsArray[ 11 ] = effectController.causticsThreshold;
    causticsArray[ 12 ] = lightPos[ 0 ];
    causticsArray[ 13 ] = lightPos[ 1 ];
    causticsArray[ 14 ] = lightPos[ 2 ];
    causticsArray[ 15 ] = effectController.causticsGain;
    device.queue.writeBuffer( causticsUniformBuffer, 0, causticsArray.buffer );

}

async function init() {

    canvas = document.createElement( 'canvas' );
    document.body.style.margin = '0';
    document.body.style.overflow = 'hidden';
    document.body.style.width = '100%';
    document.body.style.height = '100%';
    document.documentElement.style.width = '100%';
    document.documentElement.style.height = '100%';
    canvas.style.display = 'block';
    canvas.style.width = '100vw';
    canvas.style.height = '100vh';
    document.body.appendChild( canvas );

    let GUIClass = window.dat && window.dat.GUI ? window.dat.GUI : null;
    if ( ! GUIClass ) {
        const module = await import( 'https://cdn.jsdelivr.net/npm/dat.gui@0.7.9/build/dat.gui.module.js' );
        GUIClass = module.GUI || module.default || ( module.default && module.default.GUI );
    }
    gui = new GUIClass();
    gui.add( effectController, 'mouseDeep', 0.0, 1.0, 0.01 );
    gui.add( effectController, 'mouseSize', 0.02, 0.5, 0.01 );
    gui.add( effectController, 'viscosity', 0.9, 0.999, 0.001 );
    gui.add( effectController, 'speed', 1, 20, 1 );
    const causticsFolder = gui.addFolder( 'Caustics' );
    causticsFolder.add( effectController, 'causticsEnabled' );
    causticsFolder.add( effectController, 'causticsDebug' );
    causticsFolder.add( effectController, 'causticsBlurEnabled' );
    causticsFolder.add( effectController, 'causticsThreshold', 0.0, 1.0, 0.01 );
    causticsFolder.add( effectController, 'causticsGain', 0.0, 1.0, 0.01 );
    gui.add( { resetWater: () => {
        if ( ! resetHeightData ) return;
        device.queue.writeBuffer( heightBuffer0, 0, resetHeightData );
        device.queue.writeBuffer( heightBuffer1, 0, resetHeightData );
    } }, 'resetWater' );

    stats = new Stats();
    stats.showPanel( 0 );
    stats.dom.style.position = 'fixed';
    stats.dom.style.left = '8px';
    stats.dom.style.top = '8px';
    document.body.appendChild( stats.dom );

    if ( ! navigator.gpu ) {
        const info = document.createElement( 'div' );
        info.textContent = 'WebGPU not supported in this browser.';
        document.body.appendChild( info );
        return;
    }

    const shaderPaths = {
        render: 'shaders/render.wgsl',
        height: 'shaders/heightfield.wgsl',
        copy: 'shaders/heightfield-copy.wgsl',
        caustics: 'shaders/caustics.wgsl',
        blur: 'shaders/blur.wgsl'
    };
    const shaders = {};
    await Promise.all( Object.keys( shaderPaths ).map( async ( key ) => {
        const res = await fetch( shaderPaths[ key ] );
        shaders[ key ] = await res.text();
    } ) );

    const adapter = await navigator.gpu.requestAdapter();
    device = await adapter.requestDevice();
    maxTextureSize = device.limits.maxTextureDimension2D;
    context = canvas.getContext( 'webgpu' );
    canvasFormat = navigator.gpu.getPreferredCanvasFormat();

    const quadVertices = new Float32Array( [
        - 1, - 1, 1, - 1, - 1, 1,
        1, - 1, 1, 1, - 1, 1
    ] );
    quadBuffer = device.createBuffer( {
        size: quadVertices.byteLength,
        usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST
    } );
    device.queue.writeBuffer( quadBuffer, 0, quadVertices );

    const renderModule = device.createShaderModule( { code: shaders.render } );
    const heightModule = device.createShaderModule( { code: shaders.height } );
    const copyModule = device.createShaderModule( { code: shaders.copy } );
    const causticsModule = device.createShaderModule( { code: shaders.caustics } );
    const blurModule = device.createShaderModule( { code: shaders.blur } );
    const vertexBufferLayout = {
        arrayStride: 8,
        attributes: [ { shaderLocation: 0, offset: 0, format: 'float32x2' } ]
    };

    renderPipeline = device.createRenderPipeline( {
        layout: 'auto',
        vertex: { module: renderModule, entryPoint: 'vs_main', buffers: [ vertexBufferLayout ] },
        fragment: {
            module: renderModule,
            entryPoint: 'fs_main',
            targets: [ { format: canvasFormat } ]
        },
        primitive: { topology: 'triangle-list' }
    } );

    causticsPipeline = device.createRenderPipeline( {
        layout: 'auto',
        vertex: { module: causticsModule, entryPoint: 'vs_main', buffers: [ vertexBufferLayout ] },
        fragment: {
            module: causticsModule,
            entryPoint: 'fs_main',
            targets: [ { format: 'rgba16float' } ]
        },
        primitive: { topology: 'triangle-list' }
    } );

    heightPipeline = device.createComputePipeline( {
        layout: 'auto',
        compute: { module: heightModule, entryPoint: 'cs_main' }
    } );

    copyPipeline = device.createComputePipeline( {
        layout: 'auto',
        compute: { module: copyModule, entryPoint: 'cs_main' }
    } );

    blurPipeline = device.createComputePipeline( {
        layout: 'auto',
        compute: { module: blurModule, entryPoint: 'cs_main' }
    } );

    const heightData = new Float32Array( HEIGHT_RES * HEIGHT_RES * 4 );
    for ( let y = 0; y < HEIGHT_RES; y ++ ) {
        for ( let x = 0; x < HEIGHT_RES; x ++ ) {
            const index = ( y * HEIGHT_RES + x ) * 4;
            heightData[ index + 0 ] = 0.0;
            heightData[ index + 1 ] = 0.0;
            heightData[ index + 2 ] = 0.0;
            heightData[ index + 3 ] = 0.0;
        }
    }
    heightBuffer0 = device.createBuffer( {
        size: heightData.byteLength,
        usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
    } );
    heightBuffer1 = device.createBuffer( {
        size: heightData.byteLength,
        usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
    } );
    device.queue.writeBuffer( heightBuffer0, 0, heightData );
    device.queue.writeBuffer( heightBuffer1, 0, heightData );
    resetHeightData = heightData;

    heightUniformBuffer = device.createBuffer( {
        size: 32,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
    } );
    copyUniformBuffer = device.createBuffer( {
        size: 16,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
    } );
    causticsUniformBuffer = device.createBuffer( {
        size: 64,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
    } );
    blurUniformBuffer = device.createBuffer( {
        size: 16,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
    } );

    renderUniformBuffer = device.createBuffer( {
        size: 64,
        usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
    } );

    linearSampler = device.createSampler( {
        magFilter: 'linear',
        minFilter: 'linear',
        addressModeU: 'clamp-to-edge',
        addressModeV: 'clamp-to-edge'
    } );

    causticsTexture = device.createTexture( {
        size: [ CAUSTICS_SIZE, CAUSTICS_SIZE, 1 ],
        format: 'rgba16float',
        usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_DST | GPUTextureUsage.STORAGE_BINDING
    } );
    causticsBlurTexture = device.createTexture( {
        size: [ CAUSTICS_SIZE, CAUSTICS_SIZE, 1 ],
        format: 'rgba16float',
        usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.STORAGE_BINDING
    } );

    const causticsSeed = new Float32Array( CAUSTICS_SIZE * CAUSTICS_SIZE * 4 );
    for ( let y = 0; y < CAUSTICS_SIZE; y ++ ) {
        for ( let x = 0; x < CAUSTICS_SIZE; x ++ ) {
            const index = ( y * CAUSTICS_SIZE + x ) * 4;
            causticsSeed[ index + 0 ] = x / ( CAUSTICS_SIZE - 1 );
            causticsSeed[ index + 1 ] = 0.0;
            causticsSeed[ index + 2 ] = 0.0;
            causticsSeed[ index + 3 ] = 1.0;
        }
    }
    device.queue.writeTexture(
        { texture: causticsTexture },
        causticsSeed,
        { bytesPerRow: CAUSTICS_SIZE * 8, rowsPerImage: CAUSTICS_SIZE },
        { width: CAUSTICS_SIZE, height: CAUSTICS_SIZE, depthOrArrayLayers: 1 }
    );

    heightBindGroup = device.createBindGroup( {
        layout: heightPipeline.getBindGroupLayout( 0 ),
        entries: [
            { binding: 0, resource: { buffer: heightUniformBuffer } },
            { binding: 1, resource: { buffer: heightBuffer0 } },
            { binding: 2, resource: { buffer: heightBuffer1 } }
        ]
    } );

    copyBindGroup = device.createBindGroup( {
        layout: copyPipeline.getBindGroupLayout( 0 ),
        entries: [
            { binding: 0, resource: { buffer: copyUniformBuffer } },
            { binding: 1, resource: { buffer: heightBuffer1 } },
            { binding: 2, resource: { buffer: heightBuffer0 } }
        ]
    } );

    causticsBindGroup = device.createBindGroup( {
        layout: causticsPipeline.getBindGroupLayout( 0 ),
        entries: [
            { binding: 0, resource: { buffer: causticsUniformBuffer } },
            { binding: 1, resource: { buffer: heightBuffer0 } }
        ]
    } );

    blurBindGroupH = device.createBindGroup( {
        layout: blurPipeline.getBindGroupLayout( 0 ),
        entries: [
            { binding: 0, resource: linearSampler },
            { binding: 1, resource: causticsTexture.createView() },
            { binding: 2, resource: causticsBlurTexture.createView() },
            { binding: 3, resource: { buffer: blurUniformBuffer } }
        ]
    } );

    blurBindGroupV = device.createBindGroup( {
        layout: blurPipeline.getBindGroupLayout( 0 ),
        entries: [
            { binding: 0, resource: linearSampler },
            { binding: 1, resource: causticsBlurTexture.createView() },
            { binding: 2, resource: causticsTexture.createView() },
            { binding: 3, resource: { buffer: blurUniformBuffer } }
        ]
    } );

    renderBindGroup = device.createBindGroup( {
        layout: renderPipeline.getBindGroupLayout( 0 ),
        entries: [
            { binding: 0, resource: { buffer: renderUniformBuffer } },
            { binding: 1, resource: { buffer: heightBuffer0 } },
            { binding: 2, resource: linearSampler },
            { binding: 3, resource: causticsTexture.createView() }
        ]
    } );

    const lightWaveVertices = createLightWaveVertices();
    lightWaveVertexCount = lightWaveVertices.length / 2;
    lightWaveBuffer = device.createBuffer( {
        size: lightWaveVertices.byteLength,
        usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST
    } );
    device.queue.writeBuffer( lightWaveBuffer, 0, lightWaveVertices );

    canvas.addEventListener( 'pointerdown', ( e ) => {
        mouseDown = true;
        firstClick = true;
        updateOriginMouseDown = true;
        controlsEnabled = true;
        mouseX = e.clientX;
        mouseY = e.clientY;
        setMouseCoords( e.clientX, e.clientY );
        lastX = e.clientX;
        lastY = e.clientY;
        canvas.setPointerCapture( e.pointerId );
    } );

    canvas.addEventListener( 'pointermove', ( e ) => {
        if ( ! mouseDown ) {
            mouseX = e.clientX;
            mouseY = e.clientY;
            setMouseCoords( e.clientX, e.clientY );
            return;
        }

        if ( controlsEnabled ) {
            const deltaX = e.clientX - lastX;
            const deltaY = e.clientY - lastY;
            eyeCoordinate.theta += ( deltaX / 10 ) * ( Math.PI / 180 );
            eyeCoordinate.phi += ( - deltaY / 10 ) * ( Math.PI / 180 );
            eyeCoordinate.phi = Math.min( Math.max( eyeCoordinate.phi, 0.1 ), Math.PI - 0.1 );
        }
        lastX = e.clientX;
        lastY = e.clientY;
        mouseX = e.clientX;
        mouseY = e.clientY;
        setMouseCoords( e.clientX, e.clientY );
    } );

    canvas.addEventListener( 'pointerup', ( e ) => {
        mouseDown = false;
        firstClick = false;
        updateOriginMouseDown = false;
        controlsEnabled = true;
        canvas.releasePointerCapture( e.pointerId );
    } );

    canvas.addEventListener( 'pointerleave', () => {
        mouseDown = false;
        controlsEnabled = true;
    } );

    canvas.addEventListener( 'wheel', ( e ) => {
        const nextRadius = eyeCoordinate.radius + e.deltaY * 0.01;
        eyeCoordinate.radius = Math.min( Math.max( nextRadius, 1.5 ), 10.0 );
    }, { passive: true } );

    draw();

}

function draw() {

    stats.begin();

    const screen = resizeCanvas();
    raycast( screen );
    updateUniforms( screen );

    const commandEncoder = device.createCommandEncoder();
    const workgroups = Math.ceil( HEIGHT_RES / 8 );
    const computePass = commandEncoder.beginComputePass();
    computePass.setPipeline( heightPipeline );
    computePass.setBindGroup( 0, heightBindGroup );
    computePass.dispatchWorkgroups( workgroups, workgroups );
    computePass.setPipeline( copyPipeline );
    computePass.setBindGroup( 0, copyBindGroup );
    computePass.dispatchWorkgroups( workgroups, workgroups );
    computePass.end();

    const causticsPass = commandEncoder.beginRenderPass( {
        colorAttachments: [ {
            view: causticsTexture.createView(),
            loadOp: 'clear',
            storeOp: 'store',
            clearValue: { r: 0, g: 0, b: 0, a: 0 }
        } ]
    } );
    causticsPass.setPipeline( causticsPipeline );
    causticsPass.setBindGroup( 0, causticsBindGroup );
    causticsPass.setVertexBuffer( 0, lightWaveBuffer );
    causticsPass.draw( lightWaveVertexCount, 1, 0, 0 );
    causticsPass.end();

    if ( effectController.causticsBlurEnabled ) {
        const blurArray = new Float32Array( [ CAUSTICS_SIZE, CAUSTICS_SIZE, 1.0, 0.0 ] );
        device.queue.writeBuffer( blurUniformBuffer, 0, blurArray.buffer );
        const blurWorkgroups = Math.ceil( CAUSTICS_SIZE / 8 );
        const blurPassH = commandEncoder.beginComputePass();
        blurPassH.setPipeline( blurPipeline );
        blurPassH.setBindGroup( 0, blurBindGroupH );
        blurPassH.dispatchWorkgroups( blurWorkgroups, blurWorkgroups );
        blurPassH.end();

        blurArray[ 2 ] = 0.0;
        blurArray[ 3 ] = 1.0;
        device.queue.writeBuffer( blurUniformBuffer, 0, blurArray.buffer );
        const blurPassV = commandEncoder.beginComputePass();
        blurPassV.setPipeline( blurPipeline );
        blurPassV.setBindGroup( 0, blurBindGroupV );
        blurPassV.dispatchWorkgroups( blurWorkgroups, blurWorkgroups );
        blurPassV.end();
    }

    const renderPass = commandEncoder.beginRenderPass( {
        colorAttachments: [ {
            view: context.getCurrentTexture().createView(),
            loadOp: 'clear',
            storeOp: 'store',
            clearValue: { r: 0, g: 0, b: 0, a: 1 }
        } ]
    } );
    renderPass.setPipeline( renderPipeline );
    renderPass.setBindGroup( 0, renderBindGroup );
    renderPass.setVertexBuffer( 0, quadBuffer );
    renderPass.draw( 6, 1, 0, 0 );
    renderPass.end();

    device.queue.submit( [ commandEncoder.finish() ] );
    requestAnimationFrame( draw );
    stats.end();

}

init();
