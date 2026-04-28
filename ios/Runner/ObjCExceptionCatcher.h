#import <Foundation/Foundation.h>

/// Executes `block` and catches any NSException, returning it via `outException`.
/// Returns YES if the block completed without throwing, NO if an exception was caught.
BOOL tryCatchObjC(void (^_Nonnull block)(void), NSException * _Nullable * _Nullable outException);
