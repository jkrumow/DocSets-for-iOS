//
//  DocSetDownloadManager.h
//  DocSets
//
//  Created by Ole Zorn on 22.01.12.
//  Copyright (c) 2012 omz:software. All rights reserved.
//

#import <Foundation/Foundation.h>

#define DocSetDownloadManagerAvailableDocSetsChangedNotification	@"DocSetDownloadManagerAvailableDocSetsChangedNotification"
#define DocSetDownloadManagerStartedDownloadNotification			@"DocSetDownloadManagerStartedDownloadNotification"
#define DocSetDownloadManagerUpdatedDocSetsNotification				@"DocSetDownloadManagerUpdatedDocSetsNotification"
#define DocSetDownloadPausedNotification                            @"DocSetDownloadPausedNotification"
#define DocSetDownloadResumingNotification                          @"DocSetDownloadResumingNotification"
#define DocSetDownloadFinishedNotification							@"DocSetDownloadFinishedNotification"

@class DocSet, DocSetDownload;

@interface DocSetDownloadManager : NSObject {

	NSArray *_downloadedDocSets;
	NSSet *_downloadedDocSetNames;
	
	NSArray *_availableDownloads;
	NSMutableDictionary *_downloadsByURL;
	DocSetDownload *_currentDownload;
	NSMutableArray *_downloadQueue;
	
	NSDate *_lastUpdated;
	BOOL _updatingAvailableDocSetsFromWeb;
}

@property (nonatomic, strong) NSArray *downloadedDocSets;
@property (nonatomic, strong) NSSet *downloadedDocSetNames;
@property (nonatomic, strong) NSArray *availableDownloads;
@property (nonatomic, strong) DocSetDownload *currentDownload;
@property (nonatomic, strong) NSDate *lastUpdated;

+ (id)sharedDownloadManager;
- (void)reloadAvailableDocSets;
- (void)updateAvailableDocSetsFromWeb;
- (void)downloadDocSetAtURL:(NSString *)URL;
- (void)pauseCurrentDownload;
- (void)deleteDocSet:(DocSet *)docSetToDelete;
- (DocSetDownload *)downloadForURL:(NSString *)URL;
- (void)stopDownload:(DocSetDownload *)download;
- (void)pauseDownload:(DocSetDownload *)download;
- (void)resumeDownload:(DocSetDownload *)download;
- (DocSet *)downloadedDocSetWithName:(NSString *)docSetName;

@end


typedef enum DocSetDownloadStatus {
	DocSetDownloadStatusWaiting = 0,
	DocSetDownloadStatusDownloading,
    DocSetDownloadStatusDownloadPaused,
	DocSetDownloadStatusExtracting,
    DocSetDownloadStatusExtractionPaused,
	DocSetDownloadStatusFinished
} DocSetDownloadStatus;

@interface DocSetDownload : NSObject <NSURLConnectionDelegate, NSURLConnectionDataDelegate> {

	UIBackgroundTaskIdentifier _backgroundTask;
	NSURL *_URL;
	NSURLConnection *_connection;
	NSFileHandle *_fileHandle;
	NSString *_downloadTargetPath;
	NSString *_extractedPath;
	
	DocSetDownloadStatus _status;
	float _progress;
    BOOL _shouldCancelExtracting;
	NSUInteger bytesDownloaded;
	NSInteger downloadSize;
}

@property (nonatomic, strong) NSURL *URL;
@property (nonatomic, strong) NSFileHandle *fileHandle;
@property (nonatomic, strong) NSURLConnection *connection;
@property (strong) NSString *downloadTargetPath;
@property (nonatomic, strong) NSString *extractedPath;
@property (atomic, assign) DocSetDownloadStatus status;
@property (nonatomic, assign) float progress;
@property (atomic, assign) BOOL shouldCancelExtracting; // must be atomic
@property (readonly) NSUInteger bytesDownloaded;
@property (readonly) NSInteger downloadSize;
@property (nonatomic, copy) void (^expirationBlock)(void);

- (id)initWithURL:(NSURL *)URL;
- (void)start;
- (void)cancel;
- (void)pause;
- (void)resume;
- (void)failWithError:(NSError *)error;

@end