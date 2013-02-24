//
//  DownloadViewController.h
//  DocSets
//
//  Created by Ole Zorn on 22.01.12.
//  Copyright (c) 2012 omz:software. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DownloadViewController : UITableViewController {
	
}

@end


@class DocSetDownload;
@interface DownloadCell : UITableViewCell {
	NSDictionary *_downloadInfo;
	DocSetDownload *_download;
    UIView *_downloadInfoView;
	UIProgressView *_progressView;
    UIButton *_cancelDownloadButton;
}

@property (nonatomic, strong) NSDictionary *downloadInfo;
@property (nonatomic, strong) DocSetDownload *download;
@property (nonatomic, strong) UIView *downloadInfoView;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UIButton *cancelPauseDownloadButton;

- (void)setupDownloadInfoView;
- (void)updateStatusLabel;
- (void)cancelPauseDownload:(id)sender;

@end