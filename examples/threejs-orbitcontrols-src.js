/**
 * Three.js WebGPU OrbitControls Example (Source)
 *
 * This example demonstrates Three.js WebGPU renderer with OrbitControls
 * for camera rotation in MystralNative.
 *
 * REQUIREMENTS:
 *   npm install three@0.182.0
 *
 * BUNDLING (required before running):
 *   npx esbuild examples/threejs-orbitcontrols-src.js --bundle --outfile=examples/threejs-orbitcontrols-bundle.js --format=esm --platform=browser
 *
 * RUN:
 *   mystral run examples/threejs-orbitcontrols-bundle.js
 *
 * Tested with: three@0.182.0
 */

import * as THREE from 'three/webgpu';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

// MystralNative provides the canvas element globally
// TypeScript users: declare const canvas: HTMLCanvasElement;

async function main() {
  console.log('[Three.js] Starting WebGPU renderer with OrbitControls...');

  // Create WebGPU renderer using the global canvas
  const renderer = new THREE.WebGPURenderer({
    canvas: canvas,
    antialias: false,
  });

  // Initialize WebGPU (required for three/webgpu)
  await renderer.init();
  console.log('[Three.js] WebGPU initialized');

  // Setup renderer size
  const width = canvas.width || 1280;
  const height = canvas.height || 720;
  renderer.setSize(width, height, false);
  renderer.setPixelRatio(1);

  // Create scene with dark blue background
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x1a1a2e);

  // Create camera
  const camera = new THREE.PerspectiveCamera(75, width / height, 0.1, 1000);
  camera.position.z = 3;

  // Setup OrbitControls for camera rotation
  const controls = new OrbitControls(camera, canvas);
  controls.enableDamping = true; // Smooth camera movement
  controls.dampingFactor = 0.05;
  controls.enableZoom = true;
  controls.enablePan = true;
  console.log('[Three.js] OrbitControls initialized');

  // Create a green cube with standard material (PBR lighting)
  const geometry = new THREE.BoxGeometry(1, 1, 1);
  const material = new THREE.MeshStandardMaterial({
    color: 0x00ff88,
    metalness: 0.3,
    roughness: 0.4,
  });
  const cube = new THREE.Mesh(geometry, material);
  scene.add(cube);

  // Add ambient light for base illumination
  const ambientLight = new THREE.AmbientLight(0xffffff, 0.5);
  scene.add(ambientLight);

  // Add directional light for shadows and highlights
  const directionalLight = new THREE.DirectionalLight(0xffffff, 1);
  directionalLight.position.set(5, 5, 5);
  scene.add(directionalLight);

  console.log('[Three.js] Scene created, starting render loop...');

  // Animation loop
  let frameCount = 0;
  function animate() {
    frameCount++;

    // Update OrbitControls (required for damping)
    controls.update();

    // Render the scene
    renderer.render(scene, camera);

    // Log progress every 60 frames
    if (frameCount % 60 === 0) {
      console.log(`[Three.js] Frame ${frameCount}`);
    }

    requestAnimationFrame(animate);
  }

  animate();
}

main().catch((e) => {
  console.error('[Three.js] Error:', e.message);
  console.error('[Three.js] Stack:', e.stack);
});
