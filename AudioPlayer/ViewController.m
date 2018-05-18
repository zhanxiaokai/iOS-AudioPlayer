//
//  ViewController.m
//  AudioPlayer
//
//  Created by apple on 2017/2/10.
//  Copyright © 2017年 xiaokai.zhan. All rights reserved.
//

#import "ViewController.h"
#import "CommonUtil.h"
#import "AudioPlayer.h"

@implementation ViewController
{
    AudioPlayer*            _audioPlayer;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}
- (IBAction)play:(id)sender {
    NSLog(@"Play Music...");
//    NSString* filePath = [CommonUtil bundlePath:@"131.aac"];
    NSString* filePath = [CommonUtil bundlePath:@"111.aac"];
    _audioPlayer = [[AudioPlayer alloc] initWithFilePath:filePath];
    [_audioPlayer start];
}

- (IBAction)stop:(id)sender {
    NSLog(@"Stop Music...");
    if(_audioPlayer) {
         [_audioPlayer stop];
    }
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
