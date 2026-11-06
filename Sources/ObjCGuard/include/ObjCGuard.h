#import <Foundation/Foundation.h>

/// Runs a block and turns an Objective-C exception into an NSError. Swift can't catch NSExceptions,
/// and AVAudioEngine throws them (installTap on a device that's just vanished crashed Quill 5 times).
BOOL QuillTryObjC(void (NS_NOESCAPE ^_Nonnull block)(void), NSError * _Nullable * _Nullable error);
