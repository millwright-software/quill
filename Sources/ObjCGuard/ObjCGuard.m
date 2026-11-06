#import "ObjCGuard.h"

BOOL QuillTryObjC(void (NS_NOESCAPE ^block)(void), NSError **error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSString *reason = [NSString stringWithFormat:@"%@: %@", exception.name, exception.reason ?: @""];
            *error = [NSError errorWithDomain:@"QuillObjC" code:1 userInfo:@{NSLocalizedDescriptionKey: reason}];
        }
        return NO;
    }
}
