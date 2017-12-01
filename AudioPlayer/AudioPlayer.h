//
//  AudioPlayer.h
//  AudioPlayer
//
//  Created by apple on 2017/2/10.
//  Copyright © 2017年 xiaokai.zhan. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AudioPlayer : NSObject

- (id) initWithFilePath:(NSString*) filePath;

- (void) start;

- (void) stop;

@end
