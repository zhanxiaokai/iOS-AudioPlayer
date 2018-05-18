/**
 *      Setup AudioSession
 * 1: Category
 * 2: Set Listener
 *      Interrupt Listener
 *      AudioRoute Change Listener
 *      Hardwate output Volume Listener
 * 3: Set IO BufferDuration
 * 4: Active AudioSession
 *
 *      Setup AudioUnit
 * 1:Build AudioComponentDescription To Build AudioUnit Instance
 * 2:Build AudioStreamBasicDescription To Set AudioUnit Property
 * 3:Connect Node Or Set RenderCallback For AudioUnit
 * 4:Initialize AudioUnit
 * 5:Initialize AudioUnit
 * 6:AudioOutputUnitStart
 *
 **/

#import "AudioOutput.h"
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>
#import "ELAudioSession.h"
#import "CommonUtil.h"

static const AudioUnitElement inputElement = 1;
//static const AudioUnitElement outputElement = 0;

static OSStatus InputRenderCallback(void *inRefCon,
                                    AudioUnitRenderActionFlags *ioActionFlags,
                                    const AudioTimeStamp *inTimeStamp,
                                    UInt32 inBusNumber,
                                    UInt32 inNumberFrames,
                                    AudioBufferList *ioData);
static void CheckStatus(OSStatus status, NSString *message, BOOL fatal);


@interface AudioOutput(){
    SInt16*                      _outData;
}

@property(nonatomic, assign) AUGraph            auGraph;
@property(nonatomic, assign) AUNode             ioNode;
@property(nonatomic, assign) AudioUnit          ioUnit;
@property(nonatomic, assign) AUNode             convertNode;
@property(nonatomic, assign) AudioUnit          convertUnit;

@property (readwrite, copy) id<FillDataDelegate> fillAudioDataDelegate;

@end

const float SMAudioIOBufferDurationSmall = 0.0058f;

@implementation AudioOutput

- (id) initWithChannels:(NSInteger) channels sampleRate:(NSInteger) sampleRate bytesPerSample:(NSInteger) bytePerSample filleDataDelegate:(id<FillDataDelegate>) fillAudioDataDelegate;
{
    
    self = [super init];
    if (self) {
        [[ELAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback];
        [[ELAudioSession sharedInstance] setPreferredSampleRate:sampleRate];
        [[ELAudioSession sharedInstance] setActive:YES];
        [[ELAudioSession sharedInstance] setPreferredLatency:SMAudioIOBufferDurationSmall * 4];
        [[ELAudioSession sharedInstance] addRouteChangeListener];
        [self addAudioSessionInterruptedObserver];
        _outData = (SInt16 *)calloc(8192, sizeof(SInt16));
        _fillAudioDataDelegate = fillAudioDataDelegate;
        _sampleRate = sampleRate;
        _channels = channels;
        [self createAudioUnitGraph];
    }
    return self;
}

- (void)createAudioUnitGraph
{
    OSStatus status = noErr;
    
    status = NewAUGraph(&_auGraph);
    CheckStatus(status, @"Could not create a new AUGraph", YES);
    
    [self addAudioUnitNodes];
    
    status = AUGraphOpen(_auGraph);
    CheckStatus(status, @"Could not open AUGraph", YES);
    
    [self getUnitsFromNodes];
    
    [self setAudioUnitProperties];
    
    [self makeNodeConnections];
    
    CAShow(_auGraph);
    
    status = AUGraphInitialize(_auGraph);
    CheckStatus(status, @"Could not initialize AUGraph", YES);
}

- (void)addAudioUnitNodes
{
    OSStatus status = noErr;
    
    AudioComponentDescription ioDescription;
    bzero(&ioDescription, sizeof(ioDescription));
    ioDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    ioDescription.componentType = kAudioUnitType_Output;
    ioDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    
    status = AUGraphAddNode(_auGraph, &ioDescription, &_ioNode);
    CheckStatus(status, @"Could not add I/O node to AUGraph", YES);
    
    
    AudioComponentDescription convertDescription;
    bzero(&convertDescription, sizeof(convertDescription));
    ioDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    ioDescription.componentType = kAudioUnitType_FormatConverter;
    ioDescription.componentSubType = kAudioUnitSubType_AUConverter;
    status = AUGraphAddNode(_auGraph, &ioDescription, &_convertNode);
    CheckStatus(status, @"Could not add Convert node to AUGraph", YES);
}

- (void)getUnitsFromNodes
{
    OSStatus status = noErr;
    
    status = AUGraphNodeInfo(_auGraph, _ioNode, NULL, &_ioUnit);
    CheckStatus(status, @"Could not retrieve node info for I/O node", YES);
    
    
    status = AUGraphNodeInfo(_auGraph, _convertNode, NULL, &_convertUnit);
    CheckStatus(status, @"Could not retrieve node info for Convert node", YES);
}

- (void)setAudioUnitProperties
{
    OSStatus status = noErr;
    AudioStreamBasicDescription streamFormat = [self nonInterleavedPCMFormatWithChannels:_channels];
    
    status = AudioUnitSetProperty(_ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, inputElement,
                                  &streamFormat, sizeof(streamFormat));
    CheckStatus(status, @"Could not set stream format on I/O unit output scope", YES);
    
    
    AudioStreamBasicDescription _clientFormat16int;
    UInt32 bytesPerSample = sizeof (SInt16);
    bzero(&_clientFormat16int, sizeof(_clientFormat16int));
    _clientFormat16int.mFormatID          = kAudioFormatLinearPCM;
    _clientFormat16int.mFormatFlags       = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    _clientFormat16int.mBytesPerPacket    = bytesPerSample * _channels;
    _clientFormat16int.mFramesPerPacket   = 1;
    _clientFormat16int.mBytesPerFrame     = bytesPerSample * _channels;
    _clientFormat16int.mChannelsPerFrame  = _channels;
    _clientFormat16int.mBitsPerChannel    = 8 * bytesPerSample;
    _clientFormat16int.mSampleRate        = _sampleRate;
    // spectial format for converter
    status =AudioUnitSetProperty(_convertUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &streamFormat, sizeof(streamFormat));
    CheckStatus(status, @"augraph recorder normal unit set client format error", YES);
    status = AudioUnitSetProperty(_convertUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &_clientFormat16int, sizeof(_clientFormat16int));
    CheckStatus(status, @"augraph recorder normal unit set client format error", YES);
}

- (AudioStreamBasicDescription)nonInterleavedPCMFormatWithChannels:(UInt32)channels
{
    UInt32 bytesPerSample = sizeof(Float32);
    
    AudioStreamBasicDescription asbd;
    bzero(&asbd, sizeof(asbd));
    asbd.mSampleRate = _sampleRate;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    asbd.mBitsPerChannel = 8 * bytesPerSample;
    asbd.mBytesPerFrame = bytesPerSample;
    asbd.mBytesPerPacket = bytesPerSample;
    asbd.mFramesPerPacket = 1;
    asbd.mChannelsPerFrame = channels;
    
    return asbd;
}

- (void)makeNodeConnections
{
    OSStatus status = noErr;
    
    status = AUGraphConnectNodeInput(_auGraph, _convertNode, 0, _ioNode, 0);
    CheckStatus(status, @"Could not connect I/O node input to mixer node input", YES);
    
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = &InputRenderCallback;
    callbackStruct.inputProcRefCon = (__bridge void *)self;
    
    status = AudioUnitSetProperty(_convertUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
                                  &callbackStruct, sizeof(callbackStruct));
    CheckStatus(status, @"Could not set render callback on mixer input scope, element 1", YES);
}

- (void)destroyAudioUnitGraph
{
    AUGraphStop(_auGraph);
    AUGraphUninitialize(_auGraph);
    AUGraphClose(_auGraph);
    AUGraphRemoveNode(_auGraph, _ioNode);
    DisposeAUGraph(_auGraph);
    _ioUnit = NULL;
    _ioNode = 0;
    _auGraph = NULL;
}

- (BOOL)play
{
    OSStatus status = AUGraphStart(_auGraph);
    CheckStatus(status, @"Could not start AUGraph", YES);
    return YES;
}

- (void)stop
{
    OSStatus status = AUGraphStop(_auGraph);
    CheckStatus(status, @"Could not stop AUGraph", YES);
}

// AudioSession 被打断的通知
- (void)addAudioSessionInterruptedObserver
{
    [self removeAudioSessionInterruptedObserver];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onNotificationAudioInterrupted:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:[AVAudioSession sharedInstance]];
}

- (void)removeAudioSessionInterruptedObserver
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVAudioSessionInterruptionNotification
                                                  object:nil];
}

- (void)onNotificationAudioInterrupted:(NSNotification *)sender {
    AVAudioSessionInterruptionType interruptionType = [[[sender userInfo] objectForKey:AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    switch (interruptionType) {
        case AVAudioSessionInterruptionTypeBegan:
            [self stop];
            break;
        case AVAudioSessionInterruptionTypeEnded:
            [self play];
            break;
        default:
            break;
    }
}

- (void)dealloc
{
    if (_outData) {
        free(_outData);
        _outData = NULL;
    }
    
    [self destroyAudioUnitGraph];
    [self removeAudioSessionInterruptedObserver];
}

- (OSStatus)renderData:(AudioBufferList *)ioData
           atTimeStamp:(const AudioTimeStamp *)timeStamp
            forElement:(UInt32)element
          numberFrames:(UInt32)numFrames
                 flags:(AudioUnitRenderActionFlags *)flags
{
    for (int iBuffer=0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
        memset(ioData->mBuffers[iBuffer].mData, 0, ioData->mBuffers[iBuffer].mDataByteSize);
    }
    if(_fillAudioDataDelegate)
    {
        [_fillAudioDataDelegate fillAudioData:_outData numFrames:numFrames numChannels:_channels];
        for (int iBuffer=0; iBuffer < ioData->mNumberBuffers; ++iBuffer) {
            memcpy((SInt16 *)ioData->mBuffers[iBuffer].mData, _outData, ioData->mBuffers[iBuffer].mDataByteSize);
        }
    }
    return noErr;
}

@end

static OSStatus InputRenderCallback(void *inRefCon,
                                    AudioUnitRenderActionFlags *ioActionFlags,
                                    const AudioTimeStamp *inTimeStamp,
                                    UInt32 inBusNumber,
                                    UInt32 inNumberFrames,
                                    AudioBufferList *ioData)
{
    AudioOutput *audioOutput = (__bridge id)inRefCon;
    return [audioOutput renderData:ioData
                 atTimeStamp:inTimeStamp
                  forElement:inBusNumber
                numberFrames:inNumberFrames
                       flags:ioActionFlags];
}

static void CheckStatus(OSStatus status, NSString *message, BOOL fatal)
{
    if(status != noErr)
    {
        char fourCC[16];
        *(UInt32 *)fourCC = CFSwapInt32HostToBig(status);
        fourCC[4] = '\0';
        
        if(isprint(fourCC[0]) && isprint(fourCC[1]) && isprint(fourCC[2]) && isprint(fourCC[3]))
            NSLog(@"%@: %s", message, fourCC);
        else
            NSLog(@"%@: %d", message, (int)status);
        
        if(fatal)
            exit(-1);
    }
}
