//
//  AMPackInstaller.h
//  CraftyCraft
//
//  Created by John on 12/17/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AMPackInstaller : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isPackSupported:(NSURL *)url;
- (void)installPackFromURL:(NSURL *)url;
- (void)installPackFromURL:(NSURL *)url callerView:(UIView *)callerView;
@end

NS_ASSUME_NONNULL_END
