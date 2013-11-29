//
//  PitchDetectionEngine.m
//  PitchTuning
//
//  Created by Edward on 27/11/13.
//  Copyright (c) 2013 Edward. All rights reserved.
//

#import "PitchDetectionEngine.h"

@implementation PitchDetectionEngine

/* Setup the singleton Engine */
+(id)sharedEngine
{
    static PitchDetectionEngine *sharedEngine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedEngine = [[self alloc] init];
    });
    
    return sharedEngine;
}
-(id)init
{
    if(self = [super init])
        NSLog(@"Should only call once!");
    
    [self initializeAudioSession];              // Initialize Audio Session
    [self createAUProcessingGraph];             // Setup the microphone
    [self initializeAndStartProcessingGraph];   // Turn on the microphone
    
    return self;
}

/* Initialize Audio Session - Setup Sample Rate, Specify the Stream Format and FFT Setup */
- (void)initializeAudioSession
{
    NSLog(@"initializeAudioSession is called!");
    
	NSError	*err = nil;
	AVAudioSession *session = [AVAudioSession sharedInstance];
	
    sampleRate = 44100;
    
    [session setPreferredSampleRate:sampleRate error:&err];
	[session setCategory:AVAudioSessionCategoryPlayAndRecord error:&err];
	[session setActive:YES error:&err];
	
	// After activation, update our sample rate. We need to update because there
	// is a possibility the system cannot grant our request.
    sampleRate = [session sampleRate];
    
    // Allocate AudioBuffers for use when listening.
    size_t bytesPerSample = [self ASBDForSoundMode];
	bufferList = (AudioBufferList *)malloc(sizeof(AudioBuffer));
	bufferList->mNumberBuffers = 1;
	bufferList->mBuffers[0].mNumberChannels = 1;
	
	bufferList->mBuffers[0].mDataByteSize = kBufferSize*bytesPerSample;
	bufferList->mBuffers[0].mData = calloc(kBufferSize, bytesPerSample);
    
	[self realFFTSetup];
    
    NSLog(@"initializeAudioSession is done!");
}
- (size_t)ASBDForSoundMode
{
	AudioStreamBasicDescription asbd = {0};
	size_t bytesPerSample;
	bytesPerSample = sizeof(SInt16);
	asbd.mFormatID = kAudioFormatLinearPCM;
	asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	asbd.mBitsPerChannel = 8 * bytesPerSample;
	asbd.mFramesPerPacket = 1;
	asbd.mChannelsPerFrame = 1;
	asbd.mBytesPerPacket = bytesPerSample * asbd.mFramesPerPacket;
	asbd.mBytesPerFrame = bytesPerSample * asbd.mChannelsPerFrame;
	asbd.mSampleRate = sampleRate;
	
	streamFormat = asbd;
	[self printASBD:streamFormat];
	
	return bytesPerSample;
}
/* Setup our FFT */
- (void)realFFTSetup
{
	UInt32 maxFrames = 2048;                                    // Base MUST be 2!
	dataBuffer = (void*)malloc(maxFrames * sizeof(SInt16));
	outputBuffer = (float*)malloc(maxFrames *sizeof(float));

	log2n = log2f(maxFrames);
	n = 1 << log2n;

	nOver2 = maxFrames/2;
	bufferCapacity = maxFrames;
	index = 0;
	FFT.realp = (float *)malloc(nOver2 * sizeof(float));
	FFT.imagp = (float *)malloc(nOver2 * sizeof(float));
    Cepstrum.realp = (float *)malloc(nOver2 * sizeof(float));
	Cepstrum.imagp = (float *)malloc(nOver2 * sizeof(float));

    // For each FFT, the maximum sample point is 2^(log2n - 1), and at each stage,
    // N point FFT is the combined result of N/Radix FFTs!
	fftSetup = vDSP_create_fftsetup(log2n, FFT_RADIX2);
}

/* Setup the microphone and attach it with analysis callback function */
- (void)createAUProcessingGraph
{
    NSLog(@"createAUProcessingGraph is called!");
    
	OSStatus err;
    
    // Basically, this represents the microphone!
	// Configure the search parameters to find the default playback output unit
	// (called the kAudioUnitSubType_RemoteIO on iOS but
	// kAudioUnitSubType_DefaultOutput on Mac OS X)
	AudioComponentDescription ioUnitDescription;
	ioUnitDescription.componentType = kAudioUnitType_Output;
	ioUnitDescription.componentSubType = kAudioUnitSubType_RemoteIO;
	ioUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
	ioUnitDescription.componentFlags = 0;
	ioUnitDescription.componentFlagsMask = 0;
	
	// Declare and instantiate an audio processing graph
	NewAUGraph(&processingGraph);
	
	// Add an audio unit node to the graph, then instantiate the audio unit.
	/*
	 An AUNode is an opaque type that represents an audio unit in the context
	 of an audio processing graph. You receive a reference to the new audio unit
	 instance, in the ioUnit parameter, on output of the AUGraphNodeInfo
	 function call.
	 */
	AUNode ioNode;
	AUGraphAddNode(processingGraph, &ioUnitDescription, &ioNode);
	
    // Open the Graph for configuration, note: graph has to be opened before configuration and play
	AUGraphOpen(processingGraph);
	
	// Obtain a reference to the newly-instantiated I/O unit. Each Audio Unit
	// requires its own configuration.
	AUGraphNodeInfo(processingGraph, ioNode, NULL, &ioUnit);
	
	// Initialize below.
	AURenderCallbackStruct callbackStruct = {0};
	UInt32 enableInput;
	UInt32 enableOutput;
	
	// Enable input and disable output, setup the callback function to analysis audio data
	enableInput = 1; enableOutput = 0;
	callbackStruct.inputProc = AudioAnalysisCallback;
	callbackStruct.inputProcRefCon = (__bridge void*)self;
	
	err = AudioUnitSetProperty(ioUnit, kAudioOutputUnitProperty_EnableIO,
							   kAudioUnitScope_Input,
							   kInputBus, &enableInput, sizeof(enableInput));
	
	err = AudioUnitSetProperty(ioUnit, kAudioOutputUnitProperty_EnableIO,
							   kAudioUnitScope_Output,
							   kOutputBus, &enableOutput, sizeof(enableOutput));
	
	err = AudioUnitSetProperty(ioUnit, kAudioOutputUnitProperty_SetInputCallback,
							   kAudioUnitScope_Input,
							   kOutputBus, &callbackStruct, sizeof(callbackStruct));
    
	// Set the stream format of the microphone
	err = AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat,
							   kAudioUnitScope_Output,
							   kInputBus, &streamFormat, sizeof(streamFormat));
	
	err = AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat,
							   kAudioUnitScope_Input,
							   kOutputBus, &streamFormat, sizeof(streamFormat));
	
	// Disable system buffer allocation. We'll do it ourselves.
	UInt32 flag = 0;
	err = AudioUnitSetProperty(ioUnit, kAudioUnitProperty_ShouldAllocateBuffer,
                               kAudioUnitScope_Output,
                               kInputBus, &flag, sizeof(flag));
    
    NSLog(@"createAUProcessingGraph is done!");
}

/* Turn on the microphone */
- (void)initializeAndStartProcessingGraph
{
	OSStatus result = AUGraphInitialize(processingGraph);
	if (result >= 0)
		AUGraphStart(processingGraph);
	else
        NSLog(@"error initializing porcessing graph, err: %d",(int)result);
}

/*----------------------------------Audio Analysis Function-----------------------------------(Begin)*/
OSStatus AudioAnalysisCallback (void                        *inRefCon,
                                AudioUnitRenderActionFlags 	*ioActionFlags,
                                const AudioTimeStamp        *inTimeStamp,
                                UInt32 						inBusNumber,
                                UInt32 						inNumberFrames,
                                AudioBufferList				*ioData)
{
	PitchDetectionEngine* THIS = (PitchDetectionEngine *)CFBridgingRelease(inRefCon);

    /*------------Obtain Engine Parameters-----------------*/
    FFTSetup fftSetup = THIS->fftSetup;
    COMPLEX_SPLIT FFT = THIS->FFT;
    COMPLEX_SPLIT Cepstrum = THIS->Cepstrum;
	uint32_t log2n = THIS->log2n;
	uint32_t n = THIS->n;
	uint32_t nOver2 = THIS->nOver2;
    
	void *dataBuffer = THIS->dataBuffer;
	float *outputBuffer = THIS->outputBuffer;
	SInt16 index = THIS->index;
    int bufferCapacity = THIS->bufferCapacity;
    float sampleRate = THIS->sampleRate;
	
	AudioUnit rioUnit = THIS->ioUnit;
	OSStatus renderErr;
	UInt32 bus1 = 1;
    
    int i=0, j=0;
    float dominantAMP = 0;
    int bin = -1;
    
    /*------------Performance Analysis-----------------*/
    double startTime, endTime, period, frequency;
    float curAMP;

    // Obtain sampled data from microphone
	renderErr = AudioUnitRender(rioUnit, ioActionFlags, inTimeStamp, bus1, inNumberFrames, THIS->bufferList);
	if (renderErr < 0)
		return renderErr;
	
	// Fill the buffer with our sampled data. If we fill our buffer, run the fft.
	int read = bufferCapacity - index;
	if (read > inNumberFrames)
    {
		memcpy((SInt16 *)dataBuffer + index, THIS->bufferList->mBuffers[0].mData, inNumberFrames*sizeof(SInt16));
		THIS->index += inNumberFrames;
	}
    else
    {
		// If we enter this conditional, our buffer will be filled and we should
		// perform the FFT.
		memcpy((SInt16 *)dataBuffer + index, THIS->bufferList->mBuffers[0].mData, read*sizeof(SInt16));
		
		// Reset the index.
		THIS->index = 0;
		
		// We want to deal with only floating point values here.
		ConvertInt16ToFloat(THIS, dataBuffer, outputBuffer, bufferCapacity);

        /*---------------------Method 1: FFT Only---------------------(Begin)*/
        startTime = CACurrentMediaTime();
		/**
		 Look at the real signal as an interleaved complex vector by casting it.
		 Then call the transformation function vDSP_ctoz to get a split complex
		 vector, which for a real signal, divides into an even-odd configuration.
		 */
		vDSP_ctoz((COMPLEX*)outputBuffer, 2, &FFT, 1, nOver2);
		
		// Carry out a Forward FFT transform.
		vDSP_fft_zrip(fftSetup, &FFT, 1, log2n, FFT_FORWARD);
        
        // Find the frequency with the largest amplitude
        dominantAMP = 0;
		bin = -1;
        for(i=0; i<nOver2; i++)
        {
            curAMP = MagnitudeSquared(FFT.realp[i], FFT.imagp[i]);
            if(curAMP > dominantAMP)
            {
                dominantAMP = curAMP;
                bin = i;
            }
        }
     	memset(outputBuffer, 0, n*sizeof(SInt16));
        
        endTime = CACurrentMediaTime();
        period = endTime-startTime;
        frequency = bin*(sampleRate/bufferCapacity);
		NSLog(@"Method 1: Time used for FFT is %f seconds\n", period);
        NSLog(@"Method 1: Dominant frequency: %f   bin: %d \n", frequency, bin);
        NSLog(@"Method 1: Pitch: %@", [THIS midiToString:[THIS freqToMIDI:frequency]]);
		/*---------------------Method 1: FFT Only---------------------(End)*/
        
        /*---------------------Method 2: Product of FFT and Cepstrum---------------------(Begin)*/
        float* absFFTFloat = (float*)malloc(nOver2*sizeof(float));
        float* absCepstrumFloat = (float*)malloc(nOver2*sizeof(float));
        float* logABSFFTFloat = (float*)malloc(bufferCapacity*sizeof(float));
        
        startTime = CACurrentMediaTime();
        
        // absFFTFloat = abs(FFTFloat);
        vDSP_zvabs(&FFT, 1, absFFTFloat, 1, nOver2);
        
        // z = x + i*y, r = sqrt(x^2 + y^2), theta = y/x
        // log(z) = log(r) + i*theta,
        for(i=0; i<n; i+=2)
        {
            j=(i+1)/2;

            // r = sqrt(x^2 + y^2)
            logABSFFTFloat[i] = (float)log(sqrt(absFFTFloat[j]));
            
            // theta = y/x
            logABSFFTFloat[i+1] = FFT.imagp[j]/FFT.realp[j];
        }
        
        // cepstrum = fft(log(FFT)));
        vDSP_ctoz((COMPLEX*)logABSFFTFloat, 2, &Cepstrum, 1, nOver2);
        vDSP_fft_zrip(fftSetup, &Cepstrum, 1, log2n, FFT_FORWARD);
        
        // product of FFT and Cepstrum and find pitch by finding the corresponding amplitude
        vDSP_zvabs(&Cepstrum, 1, absCepstrumFloat, 1, nOver2);
        
        dominantAMP = 0;
		bin = -1;
		for(i=0; i<nOver2; i++)
        {
			float curAMP = sqrt(absFFTFloat[i]) * sqrt(absCepstrumFloat[i]);
			if (curAMP > dominantAMP)
            {
				dominantAMP = curAMP;
				bin = i;
			}
		}
        endTime = CACurrentMediaTime();
        period = endTime-startTime;
        frequency = bin*(sampleRate/bufferCapacity);
		NSLog(@"Method 2: Time used for FFT is %f seconds\n", period);
        NSLog(@"Method 2: Dominant frequency: %f   bin: %d \n", frequency, bin);
        NSLog(@"Method 2: Pitch: %@", [THIS midiToString:[THIS freqToMIDI:frequency]]);
        /*---------------------Method 2: Product of FFT and Cepstrum---------------------(Begin)*/
        
        // Should not discard the remaining samples, store the remaining data back to dataBuffer!
        int remain = inNumberFrames-read;
        if(remain > 0)
        {
            memcpy((SInt16 *)dataBuffer + index, (SInt16 *)THIS->bufferList->mBuffers[0].mData + read, remain*sizeof(SInt16));
            THIS->index += remain;
        }
	}
	
	return noErr;
}
/*----------------------------------Audio Analysis Function-----------------------------------(End)*/

#pragma mark Utility
float MagnitudeSquared(float x, float y)
{
	return ((x*x) + (y*y));
}

// ConvertInt16ToFloat(THIS, dataBuffer, outputBuffer, bufferCapacity);
void ConvertInt16ToFloat(PitchDetectionEngine* THIS, void *buf, float *outputBuf, size_t capacity)
{
	AudioConverterRef converter;
	OSStatus err;
	
	size_t bytesPerSample = sizeof(float);
	AudioStreamBasicDescription outFormat = {0};
	outFormat.mFormatID = kAudioFormatLinearPCM;
	outFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
	outFormat.mBitsPerChannel = 8 * bytesPerSample;
	outFormat.mFramesPerPacket = 1;
	outFormat.mChannelsPerFrame = 1;
	outFormat.mBytesPerPacket = bytesPerSample * outFormat.mFramesPerPacket;
	outFormat.mBytesPerFrame = bytesPerSample * outFormat.mChannelsPerFrame;
	outFormat.mSampleRate = THIS->sampleRate;
	
	const AudioStreamBasicDescription inFormat = THIS->streamFormat;
	
	UInt32 inSize = capacity*sizeof(SInt16);        // 4096
	UInt32 outSize = capacity*sizeof(float);        // 8192
    
    NSLog(@"inSize = %u", (unsigned int)inSize);
    NSLog(@"outSize = %u", (unsigned int)outSize);
    
	err = AudioConverterNew(&inFormat, &outFormat, &converter);
	err = AudioConverterConvertBuffer(converter, inSize, buf, &outSize, outputBuf);
}

- (int)freqToMIDI:(float)frequency
{
    return 12*log2f(frequency/440) + 69;
}

- (NSString*)midiToString:(int)midiNote
{
    NSArray *noteStrings = [[NSArray alloc] initWithObjects:@"C", @"C#", @"D", @"D#", @"E", @"F", @"F#", @"G", @"G#", @"A", @"A#", @"B", nil];
    NSString *retval = [noteStrings objectAtIndex:midiNote%12];
    
    if(midiNote <= 23)
        retval = [retval stringByAppendingString:@"0"];
    else if(midiNote <= 35)
        retval = [retval stringByAppendingString:@"1"];
    else if(midiNote <= 47)
        retval = [retval stringByAppendingString:@"2"];
    else if(midiNote <= 59)
        retval = [retval stringByAppendingString:@"3"];
    else if(midiNote <= 71)
        retval = [retval stringByAppendingString:@"4"];
    else if(midiNote <= 83)
        retval = [retval stringByAppendingString:@"5"];
    else if(midiNote <= 95)
        retval = [retval stringByAppendingString:@"6"];
    else if(midiNote <= 107)
        retval = [retval stringByAppendingString:@"7"];
    else
        retval = [retval stringByAppendingString:@"8"];
    
    return retval;
}


#pragma mark ForDebugOnly
- (void)printPitchDetectionEngine
{
	NSLog (@"Pitch Detection Engine - Current Value of its Parameters");
    NSLog (@"  bufferCapacity:         %zu",  bufferCapacity);
    NSLog (@"  index:                  %zu",  index);
    NSLog (@"  log2n:                  %d",   log2n);
    NSLog (@"  n:                      %d",   n);
    NSLog (@"  nOver2:                 %d",   nOver2);
    NSLog (@"  sampleRate:             %f",   sampleRate);
}

- (void)printASBD:(AudioStreamBasicDescription)asbd
{
    char formatIDString[5];
    UInt32 formatID = CFSwapInt32HostToBig (asbd.mFormatID);
    bcopy (&formatID, formatIDString, 4);
    formatIDString[4] = '\0';

	NSLog (@"Audio Stream Basic Description");
    NSLog (@"  Sample Rate:         %10.0f",   asbd.mSampleRate);
    NSLog (@"  Format ID:           %10s",     formatIDString);
    NSLog (@"  Format Flags:        %10lX",    asbd.mFormatFlags);
    NSLog (@"  Bytes per Packet:    %10ld",    asbd.mBytesPerPacket);
    NSLog (@"  Frames per Packet:   %10ld",    asbd.mFramesPerPacket);
    NSLog (@"  Bytes per Frame:     %10ld",    asbd.mBytesPerFrame);
    NSLog (@"  Channels per Frame:  %10ld",    asbd.mChannelsPerFrame);
    NSLog (@"  Bits per Channel:    %10ld",    asbd.mBitsPerChannel);
}

@end
