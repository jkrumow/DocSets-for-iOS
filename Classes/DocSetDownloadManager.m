//
//  DocSetDownloadManager.m
//  DocSets
//
//  Created by Ole Zorn on 22.01.12.
//  Copyright (c) 2012 omz:software. All rights reserved.
//

#import "NSFileManager+DocSetsAdditions.h"
#import "DocSetDownloadManager.h"
#import "DocSet.h"
#import "xar.h"
#include <sys/xattr.h>

@interface DocSetDownloadManager ()

- (void)startNextDownload;
- (void)reloadDownloadedDocSets;
- (void)downloadFinished:(DocSetDownload *)download;
- (void)downloadFailed:(DocSetDownload *)download;

@end


@implementation DocSetDownloadManager

@synthesize downloadedDocSets=_downloadedDocSets, downloadedDocSetNames=_downloadedDocSetNames, availableDownloads=_availableDownloads, currentDownload=_currentDownload, lastUpdated=_lastUpdated;

- (id)init
{
	self = [super init];
	if (self) {
		[self reloadAvailableDocSets];
		_downloadsByURL = [NSMutableDictionary new];
		_downloadQueue = [NSMutableArray new];
		[self reloadDownloadedDocSets];
	}
	return self;
}

- (void)reloadAvailableDocSets
{
	NSString *cachesPath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
	NSString *cachedAvailableDownloadsPath = [cachesPath stringByAppendingPathComponent:@"AvailableDocSets.plist"];
	NSFileManager *fm = [[NSFileManager alloc] init];
	if (![fm fileExistsAtPath:cachedAvailableDownloadsPath]) {
		NSString *bundledAvailableDocSetsPlistPath = [[NSBundle mainBundle] pathForResource:@"AvailableDocSets" ofType:@"plist"];
		[fm copyItemAtPath:bundledAvailableDocSetsPlistPath toPath:cachedAvailableDownloadsPath error:NULL];
	}
	self.lastUpdated = [[fm attributesOfItemAtPath:cachedAvailableDownloadsPath error:NULL] fileModificationDate];
	_availableDownloads = [[NSDictionary dictionaryWithContentsOfFile:cachedAvailableDownloadsPath] objectForKey:@"DocSets"];
}

- (void)updateAvailableDocSetsFromWeb
{
	if (_updatingAvailableDocSetsFromWeb) return;
	_updatingAvailableDocSetsFromWeb = YES;
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		
		NSURL *availableDocSetsURL = [NSURL URLWithString:@"https://raw.github.com/omz/DocSets-for-iOS/master/Resources/AvailableDocSets.plist"];
		NSHTTPURLResponse *response = nil;
		NSData *updatedDocSetsData = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:availableDocSetsURL] returningResponse:&response error:NULL];
		if (response.statusCode == 200) {
			NSDictionary *plist = [NSPropertyListSerialization propertyListFromData:updatedDocSetsData mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
			if (plist && [plist objectForKey:@"DocSets"]) {
				NSString *cachesPath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
				NSString *cachedAvailableDownloadsPath = [cachesPath stringByAppendingPathComponent:@"AvailableDocSets.plist"];
				[updatedDocSetsData writeToFile:cachedAvailableDownloadsPath atomically:YES];
			} else {
				//Downloaded file is somehow not a valid plist...
			}
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			_updatingAvailableDocSetsFromWeb = NO;
			[self reloadAvailableDocSets];
			[[NSNotificationCenter defaultCenter] postNotificationName:DocSetDownloadManagerAvailableDocSetsChangedNotification object:self];
		});
	});
}

- (void)reloadDownloadedDocSets
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSArray *documents = [fm contentsOfDirectoryAtPath:docPath error:NULL];
	NSMutableArray *loadedSets = [NSMutableArray array];
	for (NSString *path in documents) {
		if ([[[path pathExtension] lowercaseString] isEqual:@"docset"]) {
			NSString *fullPath = [docPath stringByAppendingPathComponent:path];
			u_int8_t b = 1;
			setxattr([fullPath fileSystemRepresentation], "com.apple.MobileBackup", &b, 1, 0, 0);
			DocSet *docSet = [[DocSet alloc] initWithPath:fullPath];
			if (docSet) [loadedSets addObject:docSet];
		}
	}
	self.downloadedDocSets = [NSArray arrayWithArray:loadedSets];
	self.downloadedDocSetNames = [NSSet setWithArray:documents];
	[[NSNotificationCenter defaultCenter] postNotificationName:DocSetDownloadManagerUpdatedDocSetsNotification object:self];
}

+ (id)sharedDownloadManager
{
	static id sharedDownloadManager = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedDownloadManager = [[self alloc] init];
	});
	return sharedDownloadManager;
}

- (DocSetDownload *)downloadForURL:(NSString *)URL
{
	return [_downloadsByURL objectForKey:URL];
}

- (void)stopDownload:(DocSetDownload *)download
{
	if (download.status == DocSetDownloadStatusWaiting) {
		[_downloadQueue removeObject:download];
		[_downloadsByURL removeObjectForKey:[download.URL absoluteString]];
		[[NSNotificationCenter defaultCenter] postNotificationName:DocSetDownloadFinishedNotification object:download];
	} else if (download.status == DocSetDownloadStatusDownloading || download.status == DocSetDownloadStatusExtracting) {
		[download cancel];
		self.currentDownload = nil;
		[_downloadsByURL removeObjectForKey:[download.URL absoluteString]];
		[[NSNotificationCenter defaultCenter] postNotificationName:DocSetDownloadFinishedNotification object:download];
		[self startNextDownload];
	}
}

- (void)pauseDownload:(DocSetDownload *)download
{
    if (download.status == DocSetDownloadStatusDownloading || download.status == DocSetDownloadStatusExtracting) {
        [download pause];
	}
}

- (void)resumeDownload:(DocSetDownload *)download
{
    if (download.status == DocSetDownloadStatusDownloadPaused || download.status == DocSetDownloadStatusExtractionPaused) {
        [download resume];
        [[NSNotificationCenter defaultCenter] postNotificationName:DocSetDownloadResumingNotification object:download];
    }
}

- (void)downloadDocSetAtURL:(NSString *)URL
{
	if ([_downloadsByURL objectForKey:URL]) {
		//already downloading
		return;
	}
	
	DocSetDownload *download = [[DocSetDownload alloc] initWithURL:[NSURL URLWithString:URL]];
	[_downloadQueue addObject:download];
	[_downloadsByURL setObject:download forKey:URL];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:DocSetDownloadManagerStartedDownloadNotification object:self];
	
	[self startNextDownload];
}

- (void)pauseCurrentDownload
{
    [self.currentDownload pause];
}

- (void)deleteDocSet:(DocSet *)docSetToDelete
{
	[[NSNotificationCenter defaultCenter] postNotificationName:DocSetWillBeDeletedNotification object:docSetToDelete userInfo:nil];
	
    NSString *tempPath = [[NSFileManager defaultManager] uniquePathInTempDirectory];
    if ([[NSFileManager defaultManager] moveItemAtPath:docSetToDelete.path toPath:tempPath error:NULL]) {
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            __block UIBackgroundTaskIdentifier backgroundTaskID = UIBackgroundTaskInvalid;
            
            // Completion block to excute when task has completed or timed out.
            void (^completionBlock)() = ^{
                [[UIApplication sharedApplication] endBackgroundTask:backgroundTaskID];
                backgroundTaskID = UIBackgroundTaskInvalid;
            };
            
            // Register background task.
            backgroundTaskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:completionBlock];
            
            NSFileManager *fileManager = [[NSFileManager alloc] init];
            [fileManager removeItemAtPath:tempPath error:NULL];
            
            // Trigger completion block when task completes.
            if (backgroundTaskID != UIBackgroundTaskInvalid)
                completionBlock();
        });
    }
    [self reloadDownloadedDocSets];
}

- (DocSet *)downloadedDocSetWithName:(NSString *)docSetName
{
	for (DocSet *docSet in _downloadedDocSets) {
		if ([[docSet.path lastPathComponent] isEqualToString:docSetName]) {
			return docSet;
		}
	}
	return nil;
}

- (void)startNextDownload
{
	if ([_downloadQueue count] == 0) {
		[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
		return;
	}
	if (self.currentDownload != nil) return;
	
	self.currentDownload = [_downloadQueue objectAtIndex:0];
	[_downloadQueue removeObjectAtIndex:0];
	
	[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
	[self.currentDownload start];
}

- (void)downloadPaused:(DocSetDownload *)download
{
    [[NSNotificationCenter defaultCenter] postNotificationName:DocSetDownloadPausedNotification object:download];
}

- (void)downloadFinished:(DocSetDownload *)download
{
	[[NSNotificationCenter defaultCenter] postNotificationName:DocSetDownloadFinishedNotification object:download];
	
	NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSArray *extractedItems = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:download.extractedPath error:NULL];
	for (NSString *file in extractedItems) {
		if ([[[file pathExtension] lowercaseString] isEqualToString:@"docset"]) {
			NSString *fullPath = [download.extractedPath stringByAppendingPathComponent:file];
			NSString *targetPath = [docPath stringByAppendingPathComponent:file];
			[[NSFileManager defaultManager] moveItemAtPath:fullPath toPath:targetPath error:NULL];
			NSLog(@"Moved downloaded docset to %@", targetPath);
		}
	}
	
	[self reloadDownloadedDocSets];
	
	[_downloadsByURL removeObjectForKey:[download.URL absoluteString]];
	self.currentDownload = nil;
	[self startNextDownload];
}

- (void)downloadFailed:(DocSetDownload *)download
{
	[[NSNotificationCenter defaultCenter] postNotificationName:DocSetDownloadFinishedNotification object:download];
	[_downloadsByURL removeObjectForKey:[download.URL absoluteString]];
	self.currentDownload = nil;
	[self startNextDownload];
	
	[[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Download Failed", nil)
                                message:NSLocalizedString(@"An error occured while trying to download the DocSet.", nil)
                               delegate:nil
                      cancelButtonTitle:NSLocalizedString(@"OK", nil)
                      otherButtonTitles:nil] show];
}

@end



@implementation DocSetDownload

@synthesize connection=_connection, URL=_URL, fileHandle=_fileHandle, downloadTargetPath=_downloadTargetPath, extractedPath=_extractedPath, progress=_progress, status=_status, shouldCancelExtracting = _shouldCancelExtracting;
@synthesize downloadSize, bytesDownloaded, expirationBlock;

- (id)initWithURL:(NSURL *)URL
{
	self = [super init];
	if (self) {
		_URL = URL;
		self.status = DocSetDownloadStatusWaiting;
	}
	return self;
}

- (void)start
{
	if (self.status != DocSetDownloadStatusWaiting) {
		return;
	}
	
    __block DocSetDownload *blockSelf = self;
    self.expirationBlock = ^{
        NSLog(@"Background process timed out.");
        [blockSelf pause];
    };
	
    _backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:self.expirationBlock];
	
	self.status = DocSetDownloadStatusDownloading;
	
	self.downloadTargetPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"download.xar"];
	[@"" writeToFile:self.downloadTargetPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.downloadTargetPath];
    
    bytesDownloaded = 0;
    self.connection = [NSURLConnection connectionWithRequest:[NSURLRequest requestWithURL:self.URL] delegate:self];
}

- (void)cancel
{
	if (self.status == DocSetDownloadStatusDownloading) {
		[self.connection cancel];
		self.status = DocSetDownloadStatusFinished;
		if (_backgroundTask != UIBackgroundTaskInvalid) {
			[[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
		}
	} else if (self.status == DocSetDownloadStatusExtracting) {
        self.shouldCancelExtracting = YES;
    }
}

- (void)pause
{
    if (self.status == DocSetDownloadStatusDownloading) {
        
        NSLog(@"Pausing download.");
        
        [self.connection cancel];
        [self.fileHandle closeFile];
        self.status = DocSetDownloadStatusDownloadPaused;
        [[DocSetDownloadManager sharedDownloadManager] downloadPaused:self];
        
        if (_backgroundTask != UIBackgroundTaskInvalid)
            [[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
        
    } else if (self.status == DocSetDownloadStatusExtracting) {
        
        NSLog(@"Pausing extraction.");
        
        self.shouldCancelExtracting = YES;
        self.status = DocSetDownloadStatusExtractionPaused;
        [[DocSetDownloadManager sharedDownloadManager] downloadPaused:self];
    }
}

- (void)resume
{
    if (self.status == DocSetDownloadStatusDownloadPaused) {
        
        NSLog(@"Resuming download.");
        
        _backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:self.expirationBlock];
        
        // Reopen file handle
        self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.downloadTargetPath];
        [self.fileHandle seekToEndOfFile];
        bytesDownloaded = [self.fileHandle offsetInFile];
        
        // Restart download with range.
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.URL];
        NSString *requestRange = [NSString stringWithFormat:@"bytes=%d-", bytesDownloaded];
        [request addValue:requestRange forHTTPHeaderField:@"Range"];
        self.connection = [NSURLConnection connectionWithRequest:request delegate:self];
        
        self.status = DocSetDownloadStatusDownloading;
        
    } else if (self.status == DocSetDownloadStatusExtractionPaused) {
        
        NSLog(@"Resuming extraction.");
        
        _backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:self.expirationBlock];
        
        [self extractDownload];
        self.status = DocSetDownloadStatusExtracting;
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	NSDictionary *headers = [(NSHTTPURLResponse *)response allHeaderFields];
	downloadSize = bytesDownloaded + [[headers objectForKey:@"Content-Length"] integerValue];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	if (self.status == DocSetDownloadStatusDownloading) {
        bytesDownloaded += [data length];
        if (downloadSize != 0) {
            self.progress = (float)bytesDownloaded / (float)downloadSize;
            //NSLog(@"Download progress: %f", self.progress);
        }
        
        @try {
            [self.fileHandle writeData:data];
        }
        @catch (NSException *exception) {
            
            // Just in case the device locks down and encryption kicks in.
            NSLog(@"%@ %@ %@", [exception name], [exception reason], [exception userInfo]);
            [self pause];
        }
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	[self.fileHandle closeFile];
	self.fileHandle = nil;
    
	self.status = DocSetDownloadStatusExtracting;
	self.progress = 0.0;
	
    [self extractDownload];
}

- (void)extractDownload {
    
    self.shouldCancelExtracting = NO;
    
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSFileManager *fm = [[NSFileManager alloc] init];
		NSString *extractionTargetPath = [[self.downloadTargetPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"xar_extract"];
		self.extractedPath = extractionTargetPath;
		[fm createDirectoryAtPath:extractionTargetPath withIntermediateDirectories:YES attributes:nil error:NULL];
		
		const char *xar_path = [self.downloadTargetPath fileSystemRepresentation];
		xar_t x = xar_open(xar_path, READ);
		
		xar_iter_t i = xar_iter_new();
		xar_file_t f = xar_file_first(x, i);
		NSInteger numberOfFiles = 1;
		do {
			f = xar_file_next(i);
			if (f != NULL) {
				numberOfFiles += 1;
			}
		} while (f != NULL);
		xar_iter_free(i);
		
		chdir([extractionTargetPath fileSystemRepresentation]);
		
		if (x == NULL) {
			NSLog(@"Could not open archive");
			[self fail];
		} else {
			xar_iter_t i = xar_iter_new();
			xar_file_t f = xar_file_first(x, i);
			NSInteger filesExtracted = 0;
			do {
				if (self.shouldCancelExtracting) {
					NSLog(@"Extracting cancelled");
					break;
				}
				if (f) {
					const char *name = NULL;
					xar_prop_get(f, "name", &name);
					int32_t extractResult = xar_extract(x, f);
					if (extractResult != 0) {
						NSLog(@"Could not extract file: %s", name);
					}
					f = xar_file_next(i);
					
					filesExtracted++;
					float extractionProgress = (float)filesExtracted / (float)numberOfFiles;
					dispatch_async(dispatch_get_main_queue(), ^{
						self.progress = extractionProgress;
					});
				}
			} while (f != NULL);
			xar_iter_free(i);
            
            if (self.shouldCancelExtracting) {
                // Cleanup: delete all files that have already been extracted
                NSFileManager *fm = [[NSFileManager alloc] init];
                [fm removeItemAtPath:extractionTargetPath error:NULL];
            }
		}
		xar_close(x);
		
        // Delete only when cancelled.
        if (self.status != DocSetDownloadStatusExtractionPaused)
            [fm removeItemAtPath:self.downloadTargetPath error:NULL];
		
		dispatch_async(dispatch_get_main_queue(), ^{
            if (self.status == DocSetDownloadStatusExtractionPaused) {
                [[DocSetDownloadManager sharedDownloadManager] downloadPaused:self];
            } else {
                self.status = DocSetDownloadStatusFinished;
                [[DocSetDownloadManager sharedDownloadManager] downloadFinished:self];
			}
			if (_backgroundTask != UIBackgroundTaskInvalid)
				[[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
		});
	});
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    if (error.code == NSURLErrorNetworkConnectionLost)
        [self pause];
    else
        [self fail];
}

- (void)fail
{
	[[DocSetDownloadManager sharedDownloadManager] downloadFailed:self];
	if (_backgroundTask != UIBackgroundTaskInvalid) {
		[[UIApplication sharedApplication] endBackgroundTask:_backgroundTask];
	}
}



@end