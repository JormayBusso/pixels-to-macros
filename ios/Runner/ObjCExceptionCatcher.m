#import "ObjCExceptionCatcher.h"

BOOL tryCatchObjC(void (^block)(void), NSException **outException) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (outException) {
            *outException = exception;
        }
        return NO;
    }
}
