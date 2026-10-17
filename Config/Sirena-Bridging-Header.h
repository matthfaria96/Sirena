//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import <AppKit/AppKit.h>

AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *identifier);

// Hidden Bar (Barra de Menus) native visibility shim
#import "../Sirena/Modules/MenuBar/Features/StatusBar/Engine/Native/HBNativeVisibilityShim.h"
