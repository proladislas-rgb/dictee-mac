#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Exécute `bloc` et rattrape une exception Objective-C (NSException) qu'AVFoundation peut lever,
/// par exemple dans -[AVAudioEngine prepare]. Swift ne sait pas rattraper ces exceptions : sans ce garde-fou, l'app s'arrête.
/// Renvoie nil si tout s'est bien passé, sinon la raison de l'exception.
NSString * _Nullable VerbeEssayer(NS_NOESCAPE void (^bloc)(void));

NS_ASSUME_NONNULL_END
