//
//  NSFileManager+DocSetsAdditions.h
//  DocSets
//
//  Created by tarbrain on 07.08.12.
//  Copyright (c) 2012 juliankrumow. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSFileManager (TemporaryDirectory)

- (NSString *)tempDirectory;

- (NSString *)uniquePathInTempDirectory;

@end
