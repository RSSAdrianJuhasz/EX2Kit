//
//  EX2FileEncryptor.m
//  EX2Kit
//
//  Created by Ben Baron on 6/29/12.
//  Copyright (c) 2012 Ben Baron. All rights reserved.
//

#import "EX2FileEncryptor.h"
#import "RNCryptor.h"
#import "EX2RingBuffer.h"
#import "DDLog.h"

@interface EX2FileEncryptor()
{
	NSString *_key;
}
@property (nonatomic, strong, readonly) EX2RingBuffer *encryptionBuffer;
@property (nonatomic, strong, readonly) NSFileHandle *fileHandle;
@end

@implementation EX2FileEncryptor

static const int ddLogLevel = LOG_LEVEL_INFO;

#define DEFAULT_CHUNK_SIZE 4096

- (id)init
{
	return [self initWithChunkSize:DEFAULT_CHUNK_SIZE];
}

- (id)initWithChunkSize:(NSUInteger)theChunkSize
{
	if ((self = [super init]))
	{
		_chunkSize = theChunkSize;
		_encryptionBuffer = [[EX2RingBuffer alloc] initWithBufferLength:_chunkSize * 10];
	}
	return self;
}

- (id)initWithPath:(NSString *)aPath chunkSize:(NSUInteger)theChunkSize key:(NSString *)theKey
{
	if ((self = [self initWithChunkSize:theChunkSize]))
	{
		_key = [theKey copy];
		_path = [aPath copy];
		_fileHandle = [NSFileHandle fileHandleForWritingAtPath:_path];
		if (_fileHandle)
		{
			[_fileHandle seekToEndOfFile];
		}
		else
		{
			// No file exists, so create one
			[[NSFileManager defaultManager] createFileAtPath:_path contents:[NSData data] attributes:nil];
			_fileHandle = [NSFileHandle fileHandleForWritingAtPath:_path];
		}
	}
	return self;
}

- (NSUInteger)writeBytes:(const void *)buffer length:(NSUInteger)length
{
	if (!self.fileHandle)
		return 0;
	
	[self.encryptionBuffer fillWithBytes:buffer length:length];
	
	NSUInteger bytesWritten = 0;
	while (self.encryptionBuffer.filledSpaceLength >= self.chunkSize)
	{
		NSData *data = [self.encryptionBuffer drainData:self.chunkSize];
		NSError *encryptionError;
		NSTimeInterval start = [[NSDate date] timeIntervalSince1970];	
		NSData *encrypted = [[RNCryptor AES256Cryptor] encryptData:data password:_key error:&encryptionError];
		DDLogVerbose(@"total time: %f", [[NSDate date] timeIntervalSince1970] - start);

		//DLog(@"data size: %u  encrypted size: %u", data.length, encrypted.length);
		if (encryptionError)
		{
			DDLogError(@"Encryptor: ERROR THERE WAS AN ERROR ENCRYPTING THIS CHUNK");
			return bytesWritten;
		}
		else
		{
			// Save the data to the file
			@try
			{
				[self.fileHandle writeData:encrypted];
				bytesWritten += self.chunkSize;
			}
			@catch (NSException *exception) 
			{
				DDLogError(@"Encryptor: Failed to write to file");
				@throw(exception);
			}
		}
	}
	
	return bytesWritten;
}

- (NSUInteger)writeData:(NSData *)data
{
	return [self writeBytes:data.bytes length:data.length];
}

- (void)clearBuffer
{
	DDLogInfo(@"Encryptor: clearing the buffer");
	[self.encryptionBuffer reset];
}

- (BOOL)closeFile
{
	DDLogInfo(@"Encryptor: closing the file");
	while (self.encryptionBuffer.filledSpaceLength > 0)
	{
		DDLogInfo(@"Encryptor: writing the remaining bytes");
		NSUInteger length = self.encryptionBuffer.filledSpaceLength >= 4096 ? 4096 : self.encryptionBuffer.filledSpaceLength;
		NSData *data = [self.encryptionBuffer drainData:length];
		
		NSError *encryptionError;
		NSData *encrypted = [[RNCryptor AES256Cryptor] encryptData:data password:_key error:&encryptionError];
		//DLog(@"data size: %u  encrypted size: %u", data.length, encrypted.length);
		if (encryptionError)
		{
			DDLogError(@"ERROR THERE WAS AN ERROR ENCRYPTING THIS CHUNK");
			//return NO;
		}
		else
		{
			// Save the data to the file
			@try
			{
				[self.fileHandle writeData:encrypted];
			}
			@catch (NSException *exception) 
			{
				//return NO;
			}
		}
	}
	
	[self.fileHandle closeFile];
	
	return YES;
}

- (NSUInteger)encryptedChunkSize
{
	NSUInteger aesPaddedSize = ((self.chunkSize / 16) + 1) * 16;
	NSUInteger totalPaddedSize = aesPaddedSize + 66; // Add the RNCryptor padding
	return totalPaddedSize;
}

- (unsigned long long)encryptedFileSizeOnDisk
{
	// Just get the size from disk
	return [[[NSFileManager defaultManager] attributesOfItemAtPath:self.path error:nil] fileSize];
}

- (unsigned long long)decryptedFileSizeOnDisk
{
	// Find the encrypted size
	unsigned long long encryptedSize = self.encryptedFileSizeOnDisk;
	
	// Find padding size
	unsigned long long chunkPadding = self.encryptedChunkSize - self.chunkSize;
	unsigned long long numberOfEncryptedChunks = (encryptedSize / self.encryptedChunkSize);
	unsigned long long filePadding = numberOfEncryptedChunks * chunkPadding;
	
	// Calculate the decrypted size
	unsigned long long decryptedSize = encryptedSize - filePadding;
	
	return decryptedSize;
}

- (NSUInteger)bytesInBuffer
{
	return self.encryptionBuffer.filledSpaceLength;
}

@end
