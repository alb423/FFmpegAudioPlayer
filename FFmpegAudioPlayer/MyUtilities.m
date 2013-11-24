//
//  MyUtilities.m
//  FFmpegAudioPlayer
//
//  Created by Liao KuoHsun on 2013/11/11.
//  Copyright (c) 2013年 Liao KuoHsun. All rights reserved.
//

#import "MyUtilities.h"

@implementation MyUtilities

+ (void) showWaiting:(UIView *) parent tag:(NSInteger) tag
{
    float screen_width = parent.frame.size.width;
    float screen_height = parent.frame.size.height;
    
    float view_width = 150.0;
    float view_height = 120.0;
    
    float view_x = (screen_width - view_width) / 2;
    float view_y = (screen_height - view_height) / 2;
    
    //==== prepare activity indicator
    int indicator_width = 32;
    int indicator_height = 32;
    CGRect frame = CGRectMake((view_width-indicator_width)/2, 30, indicator_width, indicator_height);
    UIActivityIndicatorView* progressInd = [[UIActivityIndicatorView alloc]initWithFrame:frame];
    [progressInd startAnimating];
    progressInd.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhiteLarge;
    
    
    
    //==== prepare UILabel
    frame = CGRectMake(0, 80, view_width, 20);
    
    UILabel *waitingLabel = [[UILabel alloc] initWithFrame:frame];
    waitingLabel.text = @"Please wait...";
    waitingLabel.textAlignment = NSTextAlignmentCenter;
    waitingLabel.textColor = [UIColor whiteColor];
    waitingLabel.font = [UIFont systemFontOfSize:15];
    waitingLabel.backgroundColor = [UIColor clearColor];
    
    
    //==== prepare UIView
    //NSLog(@"parent.view.width:%f parent.frame.size.height:%f", parent.frame.size.width, parent.frame.size.height);
    
    frame =  CGRectMake(view_x, view_y, view_width, view_height) ;//[parent frame];
    //NSLog(@"x:%f y:%f w:%f h:%f", view_x, view_y, view_width, view_height);
    UIView *theView = [[UIView alloc] initWithFrame:frame];
    
    theView.backgroundColor = [UIColor blackColor];
    theView.alpha = 0.8;
    [theView.layer setCornerRadius:10.0f];
    
    [theView addSubview:progressInd];
    [theView addSubview:waitingLabel];
    
    [theView setTag:tag];
    [parent addSubview:theView];
}

+ (void) showWaiting:(UIView *) parent
{
    [self showWaiting:parent tag:9999];
}

+ (void) hideWaiting:(UIView *)parent tag:(NSInteger) tag
{
    //id v =[parent viewWithTag:tag];
    
    [[parent viewWithTag:tag] removeFromSuperview];
}

+ (void) hideWaiting:(UIView *)parent
{
    [self hideWaiting:parent tag:9999];
}

+ (void) setCenterPosition:(UIView *)parent withCGPoint:(CGPoint)vCGPoint
{
    UIView *theView = [parent viewWithTag:9999];
    if(theView!=nil)
    {
        [theView setCenter:vCGPoint];
    }
    //NSLog(@"error!! wrong usage of waiting alert view");
}


@end
