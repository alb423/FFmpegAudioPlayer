//
//  MyUtilities.h
//  FFmpegAudioPlayer
//
//  Created by Liao KuoHsun on 2013/11/11.
//  Copyright (c) 2013年 Liao KuoHsun. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MyUtilities : NSObject

+ (void) showWaiting:(UIView *)parent;
+ (void) showWaiting:(UIView *) parent tag:(NSInteger) tag;

+ (void) hideWaiting:(UIView *)parent;
+ (void) hideWaiting:(UIView *)parent tag:(NSInteger) tag;

+ (void) setCenterPosition:(UIView *)parent withCGPoint:(CGPoint)vCGPoint;

@end
