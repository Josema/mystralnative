/**
 * iOS GLTF Viewer - Main Entry Point
 *
 * This demonstrates embedding the Mystral Native Runtime in an iOS app.
 * Uses SDL3 for Metal surface management and the mystral-runtime library
 * for WebGPU rendering via wgpu-native.
 *
 * Assets:
 * - DamagedHelmet.glb - The GLTF model to display
 * - sunny_rose_garden_2k.hdr - HDR environment map for IBL
 * - threejs-cube - JavaScript code that handles rendering
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

// SDL3 main entry point handling for iOS
// This header provides the main() function that calls SDL_RunApp()
// and renames our main() to SDL_main() via macro
#include <SDL3/SDL_main.h>

#include "mystral/runtime.h"
#include <fstream>
#include <sstream>
#include <cstdio>  // For fprintf

// Early debug logging (writes to stderr immediately, before any ObjC setup)
#define DEBUG_LOG(fmt, ...) do { \
    fprintf(stderr, "[MystralGLTF] " fmt "\n", ##__VA_ARGS__); \
    fflush(stderr); \
} while(0)

// ============================================================================
// FPS Counter Overlay
// ============================================================================

@interface FPSOverlayView : UIView {
    UILabel *fpsLabel;
    CADisplayLink *displayLink;
    CFTimeInterval lastTimestamp;
    NSInteger frameCount;
    NSInteger currentFPS;
}
- (void)startTracking;
- (void)stopTracking;
@end

@implementation FPSOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        
        // Create FPS label with rounded background
        UIView *bgView = [[UIView alloc] initWithFrame:CGRectMake(10, 50, 100, 32)];
        bgView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        bgView.layer.cornerRadius = 6;
        bgView.clipsToBounds = YES;
        [self addSubview:bgView];
        
        fpsLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 100, 32)];
        fpsLabel.text = @"FPS: --";
        fpsLabel.textColor = [UIColor greenColor];
        fpsLabel.font = [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightBold];
        fpsLabel.textAlignment = NSTextAlignmentCenter;
        [bgView addSubview:fpsLabel];
        
        frameCount = 0;
        currentFPS = 0;
        lastTimestamp = 0;
    }
    return self;
}

- (void)startTracking {
    displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    lastTimestamp = CACurrentMediaTime();
    NSLog(@"FPS tracking started");
}

- (void)stopTracking {
    [displayLink invalidate];
    displayLink = nil;
}

- (void)tick:(CADisplayLink *)link {
    frameCount++;
    
    CFTimeInterval currentTime = CACurrentMediaTime();
    CFTimeInterval elapsed = currentTime - lastTimestamp;
    
    // Update FPS every 0.5 seconds
    if (elapsed >= 0.5) {
        currentFPS = (NSInteger)(frameCount / elapsed);
        frameCount = 0;
        lastTimestamp = currentTime;
        
        // Update label
        fpsLabel.text = [NSString stringWithFormat:@"FPS: %ld", (long)currentFPS];
        
        // Color based on performance
        if (currentFPS >= 55) {
            fpsLabel.textColor = [UIColor greenColor];
        } else if (currentFPS >= 30) {
            fpsLabel.textColor = [UIColor yellowColor];
        } else {
            fpsLabel.textColor = [UIColor redColor];
        }
    }
}

@end

// Global FPS overlay reference
static FPSOverlayView *g_fpsOverlay = nil;

// Setup FPS overlay on main window
static void setupFPSOverlay() {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Find the key window
        UIWindow *keyWindow = nil;
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *window in scene.windows) {
                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
                }
            }
        }
        
        if (!keyWindow) {
            // Fallback: get first window
            UIWindowScene *scene = (UIWindowScene *)[[[UIApplication sharedApplication] connectedScenes] anyObject];
            if (scene && [scene isKindOfClass:[UIWindowScene class]]) {
                keyWindow = scene.windows.firstObject;
            }
        }
        
        if (keyWindow) {
            g_fpsOverlay = [[FPSOverlayView alloc] initWithFrame:keyWindow.bounds];
            [keyWindow addSubview:g_fpsOverlay];
            [g_fpsOverlay startTracking];
            NSLog(@"FPS overlay added to window");
        } else {
            NSLog(@"WARNING: Could not find window for FPS overlay");
        }
    });
}

// Read file contents from the app bundle
static std::string readBundleFile(NSString* filename) {
    NSBundle* bundle = [NSBundle mainBundle];
    NSString* path = [bundle pathForResource:[filename stringByDeletingPathExtension]
                                      ofType:[filename pathExtension]];
    if (!path) {
        NSLog(@"Could not find %@ in bundle", filename);
        return "";
    }

    NSString* contents = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
    if (!contents) {
        NSLog(@"Could not read %@", filename);
        return "";
    }

    return std::string([contents UTF8String]);
}

// Get path to asset in bundle
static std::string getBundleAssetPath(NSString* filename) {
    NSBundle* bundle = [NSBundle mainBundle];
    NSString* path = [bundle pathForResource:[filename stringByDeletingPathExtension]
                                      ofType:[filename pathExtension]];
    if (!path) {
        NSLog(@"Could not find %@ in bundle", filename);
        return "";
    }
    return std::string([path UTF8String]);
}

// Main function - SDL_main.h renames this to SDL_main via macro
// and provides the actual main() that calls SDL_RunApp()
int main(int argc, char *argv[]) {
    DEBUG_LOG("SDL_main entry - argc=%d", argc);

    @autoreleasepool {
        DEBUG_LOG("Entered @autoreleasepool");
        NSLog(@"=== Mystral iOS GLTF Viewer ===");
        DEBUG_LOG("After first NSLog");
        NSLog(@"Version: %s", mystral::getVersion());
        DEBUG_LOG("Version: %s", mystral::getVersion());

        // Get screen size for the runtime config
        CGRect screenBounds = [[UIScreen mainScreen] bounds];
        CGFloat scale = [[UIScreen mainScreen] scale];
        int width = (int)(screenBounds.size.width * scale);
        int height = (int)(screenBounds.size.height * scale);

        NSLog(@"Screen: %dx%d (scale: %.1f)", width, height, scale);
        DEBUG_LOG("Screen: %dx%d (scale: %.1f)", width, height, scale);

        // Configure the runtime
        DEBUG_LOG("Creating RuntimeConfig...");
        mystral::RuntimeConfig config;
        config.width = width;
        config.height = height;
        config.title = "GLTF Viewer";
        config.fullscreen = true;  // iOS apps are fullscreen
        config.vsync = true;
        DEBUG_LOG("RuntimeConfig ready, calling Runtime::create()...");

        // Create the runtime
        auto runtime = mystral::Runtime::create(config);
        DEBUG_LOG("Runtime::create() returned %s", runtime ? "success" : "NULL");
        if (!runtime) {
            DEBUG_LOG("FAILED to create runtime!");
            NSLog(@"Failed to create runtime!");
            return 1;
        }

        DEBUG_LOG("Runtime created successfully");
        NSLog(@"Runtime created successfully");

        // Get asset paths
        std::string gltfPath = getBundleAssetPath(@"DamagedHelmet.glb");
        std::string envMapPath = getBundleAssetPath(@"sunny_rose_garden_2k.hdr");

        if (gltfPath.empty() || envMapPath.empty()) {
            NSLog(@"Missing assets! Make sure DamagedHelmet.glb and sunny_rose_garden_2k.hdr are in the bundle.");
            return 1;
        }

        NSLog(@"GLTF path: %s", gltfPath.c_str());
        NSLog(@"Environment map path: %s", envMapPath.c_str());
        DEBUG_LOG("GLTF path: %s", gltfPath.c_str());
        DEBUG_LOG("Env map path: %s", envMapPath.c_str());

        // Set global paths for the JavaScript code
        DEBUG_LOG("Setting up asset path globals...");
        std::string setupCode = R"(
            globalThis.__GLTF_PATH__ = ")" + gltfPath + R"(";
            globalThis.__ENV_MAP_PATH__ = ")" + envMapPath + R"(";
            console.log("Asset paths configured");
        )";

        if (!runtime->evalScript(setupCode, "setup.js")) {
            DEBUG_LOG("FAILED to set up asset paths!");
            NSLog(@"Failed to set up asset paths!");
            return 1;
        }
        DEBUG_LOG("Asset path globals set successfully");

        // Load and run the main JavaScript code
        DEBUG_LOG("Loading threejs-cube.js...");
        std::string jsCode = readBundleFile(@"threejs-cube.js");
        if (jsCode.empty()) {
            DEBUG_LOG("FAILED to load threejs-cube.js!");
            NSLog(@"Failed to load threejs-cube.js from bundle!");
            return 1;
        }

        NSLog(@"Loaded JavaScript: %lu bytes", jsCode.length());
        DEBUG_LOG("Loaded JavaScript: %lu bytes", jsCode.length());

        DEBUG_LOG("Evaluating threejs-cube...");
        if (!runtime->evalScript(jsCode, "threejs-cube")) {
            DEBUG_LOG("FAILED to evaluate JavaScript!");
            NSLog(@"Failed to evaluate JavaScript!");
            return 1;
        }

        DEBUG_LOG("JavaScript evaluated successfully");
        NSLog(@"JavaScript loaded, starting main loop");
        DEBUG_LOG("Starting main loop...");

        // Setup FPS overlay before starting the main loop
        setupFPSOverlay();

        // Run the main loop - this blocks until quit
        runtime->run();

        // Cleanup FPS overlay
        if (g_fpsOverlay) {
            [g_fpsOverlay stopTracking];
            [g_fpsOverlay removeFromSuperview];
            g_fpsOverlay = nil;
        }

        DEBUG_LOG("Main loop exited");
        NSLog(@"=== Application finished ===");
        return 0;
    }
}
