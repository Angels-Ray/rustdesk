#pragma once

#import <Cocoa/Cocoa.h>
#import <objc/objc.h>
#import <objc/runtime.h>

// cbindgen emits objc::runtime::Object and Sel in the C header.
typedef id Object;
typedef SEL Sel;

#include "bridge_generated.h"
