//
//  NSFileManager+DocSetsAdditions.m
//  DocSets
//
//  Created by tarbrain on 07.08.12.
//  Copyright (c) 2012 juliankrumow. All rights reserved.
//

#import "NSFileManager+DocSetsAdditions.h"

@implementation NSFileManager (DocSetsAdditions)

- (NSString *)tempDirectory
{
	static dispatch_once_t onceToken;
	static NSString *cachedTempPath;
	
	dispatch_once(&onceToken, ^{
		cachedTempPath = NSTemporaryDirectory();
	});
	
	return cachedTempPath;
}

- (NSString *)uniquePathInTempDirectory
{
	CFUUIDRef uniqueId = CFUUIDCreate(kCFAllocatorDefault);
	CFStringRef uniqueIdString = CFUUIDCreateString(kCFAllocatorDefault, uniqueId);
	NSString *tempPath = [[self tempDirectory] stringByAppendingPathComponent:(__bridge NSString *)uniqueIdString];
	CFRelease(uniqueId);
	CFRelease(uniqueIdString);
	
	return tempPath;
}

@end
