//
//  DownloadViewController.m
//  DocSets
//
//  Created by Ole Zorn on 22.01.12.
//  Copyright (c) 2012 omz:software. All rights reserved.
//

#import "DownloadViewController.h"
#import "DocSetDownloadManager.h"

@implementation DownloadViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
		self.title = NSLocalizedString(@"Download", nil);
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(docSetsChanged:) name:DocSetDownloadManagerUpdatedDocSetsNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(availableDocSetsChanged:) name:DocSetDownloadManagerAvailableDocSetsChangedNotification object:nil];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	self.tableView.rowHeight = 64.0;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done:)];
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(updateAvailableDocSetsFromWeb:)];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
		return YES;
	}
	return UIInterfaceOrientationIsLandscape(interfaceOrientation) || (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)docSetsChanged:(NSNotification *)notification
{
	[self.tableView reloadData];
}

- (void)availableDocSetsChanged:(NSNotification *)notification
{
	self.navigationItem.leftBarButtonItem.enabled = YES;
	[self.tableView reloadData];
}

- (void)updateAvailableDocSetsFromWeb:(id)sender
{
	self.navigationItem.leftBarButtonItem.enabled = NO;
	[[DocSetDownloadManager sharedDownloadManager] updateAvailableDocSetsFromWeb];
}

- (void)done:(id)sender
{
	[self dismissModalViewControllerAnimated:YES];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return [[[DocSetDownloadManager sharedDownloadManager] availableDownloads] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    
    DownloadCell *cell = (DownloadCell *)[tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
		cell = [[DownloadCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
		cell.detailTextLabel.lineBreakMode = UILineBreakModeMiddleTruncation;
    }
	
    NSDictionary *downloadInfo = [[[DocSetDownloadManager sharedDownloadManager] availableDownloads] objectAtIndex:indexPath.row];
	cell.downloadInfo = downloadInfo;
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
	return [NSString stringWithFormat:NSLocalizedString(@"Last updated: %@", nil), [NSDateFormatter localizedStringFromDate:[[DocSetDownloadManager sharedDownloadManager] lastUpdated] dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	
	NSDictionary *downloadInfo = [[[DocSetDownloadManager sharedDownloadManager] availableDownloads] objectAtIndex:indexPath.row];
	
	NSString *name = [downloadInfo objectForKey:@"name"];
	BOOL downloaded = [[[DocSetDownloadManager sharedDownloadManager] downloadedDocSetNames] containsObject:name];
	if (downloaded) {
		[[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Already Downloaded", nil)
                                    message:NSLocalizedString(@"You have already downloaded this DocSet.", nil)
                                   delegate:nil
                          cancelButtonTitle:NSLocalizedString(@"OK", nil)
                          otherButtonTitles:nil] show];
	} else {
		NSString *docSetURL = [downloadInfo objectForKey:@"URL"];
		[[DocSetDownloadManager sharedDownloadManager] downloadDocSetAtURL:docSetURL];
	}
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end



@implementation DownloadCell

@synthesize downloadInfo=_downloadInfo, download=_download, downloadInfoView=_downloadInfoView, progressView=_progressView, cancelPauseDownloadButton=_cancelDownloadButton;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadStarted:) name:DocSetDownloadManagerStartedDownloadNotification object:nil];
		[self setupDownloadInfoView];
		
	}
	return self;
}

- (void)setupDownloadInfoView
{
    CGFloat progressViewWidth = ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) ? 120 : 70;
    CGFloat cancelButtonWidth = 30;
    CGFloat cancelButtonHeight = 29;
    CGFloat margin = 10;
    
    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
	
    _cancelDownloadButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _cancelDownloadButton.frame = CGRectMake(progressViewWidth + margin, 0, cancelButtonWidth, cancelButtonHeight);
    [self updateCancelPauseDownloadButtonImage];
    [_cancelDownloadButton addTarget:self action:@selector(cancelPauseDownload:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)updateCancelPauseDownloadButtonImage
{
    if (self.download.status == DocSetDownloadStatusDownloadPaused || self.download.status == DocSetDownloadStatusExtractionPaused) {
        [self.cancelPauseDownloadButton setImage:[UIImage imageNamed:@"Pause.png"] forState:UIControlStateNormal];
        [self.cancelPauseDownloadButton setImage:[UIImage imageNamed:@"Pause-Pressed.png"] forState:UIControlStateHighlighted];
        [self.cancelPauseDownloadButton setImage:[UIImage imageNamed:@"Pause-Pressed.png"] forState:UIControlStateSelected];
    } else {
        [self.cancelPauseDownloadButton setImage:[UIImage imageNamed:@"Cancel.png"] forState:UIControlStateNormal];
        [self.cancelPauseDownloadButton setImage:[UIImage imageNamed:@"Cancel-Pressed.png"] forState:UIControlStateHighlighted];
        [self.cancelPauseDownloadButton setImage:[UIImage imageNamed:@"Cancel-Pressed.png"] forState:UIControlStateSelected];
    }
}

- (void)layoutSubviews
{
	[super layoutSubviews];
	if (!self.download) {
		return;
	}
	DocSetDownloadStatus status = self.download.status;
	if (status == DocSetDownloadStatusWaiting || status == DocSetDownloadStatusDownloading || status == DocSetDownloadStatusDownloadPaused || status == DocSetDownloadStatusExtracting || status == DocSetDownloadStatusExtractionPaused) {
		self.progressView.frame = CGRectMake(60, CGRectGetMidY(self.contentView.bounds) - self.progressView.bounds.size.height * 0.5, CGRectGetWidth(self.contentView.bounds) - 70, self.progressView.frame.size.height);
		CGRect textLabelFrame = self.textLabel.frame;
		self.textLabel.frame = CGRectMake(textLabelFrame.origin.x, 3, textLabelFrame.size.width, textLabelFrame.size.height);
		CGRect detailLabelFrame = self.detailTextLabel.frame;
		self.detailTextLabel.frame = CGRectMake(detailLabelFrame.origin.x, self.contentView.bounds.size.height - CGRectGetHeight(detailLabelFrame) - 3, detailLabelFrame.size.width, detailLabelFrame.size.height);
	}
}

- (void)downloadStarted:(NSNotification *)notification
{
	if (!self.download)
		self.download = [[DocSetDownloadManager sharedDownloadManager] downloadForURL:[self.downloadInfo objectForKey:@"URL"]];
}

- (void)downloadPaused:(NSNotification *)notification
{
    if (notification.object == self.download)
        [self updateCancelPauseDownloadButtonImage];
}

- (void)downloadResuming:(NSNotification *)notification
{
    if (notification.object == self.download)
        [self updateCancelPauseDownloadButtonImage];
}

- (void)downloadFinished:(NSNotification *)notification
{
	if (notification.object == self.download)
		self.download = nil;
}

- (void)setDownloadInfo:(NSDictionary *)downloadInfo
{
	_downloadInfo = downloadInfo;
	NSString *URL = [_downloadInfo objectForKey:@"URL"];
	NSString *name = [_downloadInfo objectForKey:@"name"];
	BOOL downloaded = [[[DocSetDownloadManager sharedDownloadManager] downloadedDocSetNames] containsObject:name];
	if (downloaded) {
		self.textLabel.textColor = [UIColor grayColor];
	} else {
		self.textLabel.textColor = [UIColor blackColor];
	}
	self.download = [[DocSetDownloadManager sharedDownloadManager] downloadForURL:URL];
	
	self.textLabel.text = [_downloadInfo objectForKey:@"title"];
	self.imageView.image = [UIImage imageNamed:@"DocSet.png"];
}

- (void)setDownload:(DocSetDownload *)download
{
	if (_download) {
		[_download removeObserver:self forKeyPath:@"progress"];
		[_download removeObserver:self forKeyPath:@"status"];
		[[NSNotificationCenter defaultCenter] removeObserver:self name:DocSetDownloadFinishedNotification object:_download];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:DocSetDownloadPausedNotification object:_download];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:DocSetDownloadResumingNotification object:_download];
	}
	
	_download = download;
	[_download addObserver:self forKeyPath:@"progress" options:NSKeyValueObservingOptionNew context:nil];
	[_download addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadFinished:) name:DocSetDownloadFinishedNotification object:_download];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadPaused:) name:DocSetDownloadPausedNotification object:_download];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadResuming:) name:DocSetDownloadResumingNotification object:_download];
	
	if (_download) {
		self.textLabel.font = [UIFont boldSystemFontOfSize:15.0];
		self.progressView.progress = self.download.progress;
		self.accessoryView = self.cancelPauseDownloadButton;
		[self.contentView addSubview:self.progressView];
	} else {
		self.textLabel.font = [UIFont boldSystemFontOfSize:18.0];
		self.accessoryView = nil;
		[self.progressView removeFromSuperview];
	}
    [self updateCancelPauseDownloadButtonImage];
	[self updateStatusLabel];
}

- (void)updateStatusLabel
{
	if (!self.download) {
		self.detailTextLabel.text = nil;
	} else if (self.download.status == DocSetDownloadStatusWaiting) {
		self.detailTextLabel.text = NSLocalizedString(@"Waiting...", nil);
	} else if (self.download.status == DocSetDownloadStatusDownloading) {
		NSInteger downloadSize = self.download.downloadSize;
		NSUInteger bytesDownloaded = self.download.bytesDownloaded;
		if (downloadSize != 0) {
			NSString *totalMegabytes = [NSString stringWithFormat:@"%.01f", (float)(downloadSize / pow(2, 20))];
			NSString *downloadedMegabytes = [NSString stringWithFormat:@"%.01f", (float)(bytesDownloaded / pow(2, 20))];
			if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
				self.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Downloading... (%@ MB / %@ MB)", nil), downloadedMegabytes, totalMegabytes];
			} else {
				self.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"%@ MB / %@ MB", nil), downloadedMegabytes, totalMegabytes];
			}
		} else {
			self.detailTextLabel.text = NSLocalizedString(@"Downloading...", nil);
		}
	} else if (self.download.status == DocSetDownloadStatusDownloadPaused || self.download.status == DocSetDownloadStatusExtractionPaused) {
        self.detailTextLabel.text = NSLocalizedString(@"Paused...", nil);
    } else if (self.download.status == DocSetDownloadStatusExtracting) {
		int extractedPercentage = (int)(self.download.progress * 100);
		if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
			self.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Extracting Download... (%i%%)", nil), extractedPercentage];
		} else {
			self.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Extracting (%i%%)", nil), extractedPercentage];
		}
	} else {
		self.detailTextLabel.text = nil;
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath isEqualToString:@"progress"]) {
		self.progressView.progress = self.download.progress;
		[self updateStatusLabel];
	} else if ([keyPath isEqualToString:@"status"]) {
		[self updateStatusLabel];
	}
}

- (void)cancelPauseDownload:(id)sender
{
    if (self.download.status == DocSetDownloadStatusDownloadPaused || self.download.status == DocSetDownloadStatusExtractionPaused)
        [[DocSetDownloadManager sharedDownloadManager] resumeDownload:self.download];
    else
        [[DocSetDownloadManager sharedDownloadManager] stopDownload:self.download];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_download removeObserver:self forKeyPath:@"progress"];
	[_download removeObserver:self forKeyPath:@"status"];
}

@end