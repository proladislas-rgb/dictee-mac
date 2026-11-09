#import "VerbeObjC.h"

NSString * _Nullable VerbeEssayer(NS_NOESCAPE void (^bloc)(void)) {
    @try {
        bloc();
        return nil;
    } @catch (NSException *exception) {
        return [NSString stringWithFormat:@"%@ : %@", exception.name, exception.reason ?: @"(sans raison)"];
    }
}
