//
//  NSView+Snapshotting.h
//  DetoxInstruments
//
//  Created by Leo Natan (Wix) on 5/9/18.
//  Copyright © 2018 Wix. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSView (Snapshotting)

- (NSImage*)snapshotForCachingDisplay;

@end
