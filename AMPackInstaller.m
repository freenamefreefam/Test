//
//  AMPackInstaller.m
//  CraftyCraft
//
//  Created by John on 12/17/19.
//

#import "AMPackInstaller.h"
#import "SSZipArchive.h"
#import "DirectAccessViewController.h"
#import "DirectAccess.h"
#import "AMExportViewController.h"
#import "NYAlertViewControllerOrig.h"

#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v)              ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v)                 ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)

@interface AMPackInstaller()
@property UIDocumentInteractionController *interactionController;
@end

@implementation AMPackInstaller

+ (instancetype)sharedInstance {
    static AMPackInstaller *sharedInstance = nil;
    static dispatch_once_t onceToken; // onceToken = 0
    dispatch_once(&onceToken, ^{
        sharedInstance = [[AMPackInstaller alloc] init];
    });
    
    return sharedInstance;
}

- (NSArray *)supportedFormats{
    NSArray *formats = @[@"mcpack", @"mcaddon", @"zip", @"mcworld", @"mctemplate"];
    return formats;
}

- (void)installPackFromURL:(NSURL *)url{
    CGRect frame = CGRectMake([UIScreen mainScreen].bounds.size.width / 2.0, [UIScreen mainScreen].bounds.size.height / 2.0, 1, 1);
    UIView *v = [[UIView alloc] initWithFrame:frame];
    [self installPackFromURL:url callerView:v];
}

- (void)installPackFromURL:(NSURL *)url callerView:(UIView *)callerView{
    // 1. check supported
    if (![self isPackSupported:url]) {
        NSString *mesage = [NSString stringWithFormat:@"%@ not suported", url];
        [[[NYAlertViewControllerOrig alloc] initWithTitle:@"Unknown pack format" message:mesage delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        return;
    }
    
    //scrim in library pentru instalare normala, fara asta nihuia nu o sa lucreze
    NSString *libraryDirectory = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    NSFileManager *fM = [NSFileManager defaultManager];
    NSString *tempDownloadPath = [libraryDirectory stringByAppendingPathComponent:@"DownloadTemp"];
    if ([fM fileExistsAtPath:tempDownloadPath]) {
        [fM removeItemAtPath:tempDownloadPath error:nil];
    }
    [fM createDirectoryAtPath:tempDownloadPath withIntermediateDirectories:YES attributes:nil error:nil];
    tempDownloadPath = [tempDownloadPath stringByAppendingPathComponent:@"Generated"];
    [fM createDirectoryAtPath:tempDownloadPath withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *localFilePath = [tempDownloadPath stringByAppendingPathComponent:url.lastPathComponent];
    if ([url respondsToSelector:@selector(startAccessingSecurityScopedResource)]) {
        [url startAccessingSecurityScopedResource]; //numaidecit
    }
    NSData *data = [NSData dataWithContentsOfURL:url];
    if ([url respondsToSelector:@selector(startAccessingSecurityScopedResource)]) {
        [url stopAccessingSecurityScopedResource];
    }
    [data writeToFile:localFilePath atomically:YES];
    
    //mai intii ne uitam daca nu e ios13, in cazu ista packete se transmit la document controller
    if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"13.0")) {
        NSURL *url = [NSURL fileURLWithPath:localFilePath];
        self.interactionController = [UIDocumentInteractionController interactionControllerWithURL:url];
        [self.interactionController presentOptionsMenuFromRect:CGRectMake(0, 0, callerView.frame.size.width, callerView.frame.size.height) inView:callerView animated:YES];
        return;
    }
    
    // pornim analiza la tipu paketului
    NSMutableDictionary *resultDict = [NSMutableDictionary new];
    [self analisePath:localFilePath resultDict:&resultDict];
    
    NSLog(@"result dict = %@", resultDict);
    
    //daca este world inseamna ca restu is prisos, trebuie instalat numai worldu
    if (resultDict[@"world_pack"]) {
        if ([[DirectAccess sharedInstance] isAccessGranted]) {
            [self writeWorldAtPath:localFilePath toUrl:[[DirectAccess sharedInstance] getUrlAccess]];
        }else{
            //request access
            [DirectAccessViewController showWithCompletition:^(BOOL granted) {
                if (granted) {
                    [self writeWorldAtPath:localFilePath toUrl:[[DirectAccess sharedInstance] getUrlAccess]];
                }
            }];
        }
    }else{
        [AMExportViewController showWithPathParameters:resultDict];
    }
    
    [[NSFileManager defaultManager] removeItemAtPath:localFilePath error:nil];
}

- (void)writeWorldAtPath:(NSString *) path toUrl:(NSURL *)url{
    [url startAccessingSecurityScopedResource]; //numaidecit
     
     NSString *name = [path.lastPathComponent stringByDeletingPathExtension];
     
     NSURL *worldURL = [url URLByAppendingPathComponent:[@"games/com.mojang/minecraftWorlds/" stringByAppendingString:name]];
     
    NSMutableArray *errorArray = [NSMutableArray new];
    
    NSString *unzippedPath = [path stringByDeletingPathExtension];
    [SSZipArchive unzipFileAtPath:path toDestination:unzippedPath];
    NSArray *elements = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:unzippedPath error:nil];
    if (elements.count == 1) {
        unzippedPath = [unzippedPath stringByAppendingPathComponent:elements[0]];
    }
   
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtURL:worldURL error:nil];
    [[NSFileManager defaultManager] copyItemAtURL:[NSURL fileURLWithPath:unzippedPath] toURL:worldURL error:&error];
    if (error) {
        NSLog(@"error = %@", error.description);
        [errorArray addObject:error];
    }
    
    [url stopAccessingSecurityScopedResource];
    
    if (errorArray.count == 0) {
        [[[NYAlertViewControllerOrig alloc] initWithTitle:@"Install successful" message:@"Now RESTART\nthe Minecraft Game" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }else{
        [[[NYAlertViewControllerOrig alloc] initWithTitle:@"Error" message:[NSString stringWithFormat:@"%@", errorArray] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }
}


#pragma mark - Analizator
- (BOOL)isPackSupported:(NSURL *)url{
    NSArray *formats = [self supportedFormats];
    NSString *fileFormat = url.pathExtension;
    if (![formats containsObject:fileFormat]) {
        return NO;
    }
    return YES;
}

- (void)analisePath:(NSString *)path resultDict:(NSMutableDictionary **)dict{
    NSString *pathExtension = path.pathExtension;
    NSArray *formats = [self supportedFormats];
    
    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    
    if (!isDir) {
        if ([formats containsObject:pathExtension]) {
            NSString *unzippedPath = [path stringByDeletingPathExtension];
            [SSZipArchive unzipFileAtPath:path toDestination:unzippedPath];
            [self analisePath:unzippedPath resultDict:dict];
        }
    }else{
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
        // avel lista de file-uri din directoriu, trebu de spalit ce za directoriu ii aista, de care tip
        
        // controlam daca e directoriu cu skinuri
        if ([self isSkinPack:path]) {
            [*dict setObject:path forKey:@"skin_pack"];
            return;
        }
        
        //controlam daca e behavior pack
        if ([self isBehaviorPack:path]) {
            [*dict setObject:path forKey:@"behavior_pack"];
            return;
        }
        
        //controlam daca e resource pack
        if ([self isResourcePack:path]) {
            [*dict setObject:path forKey:@"resource_pack"];
            return;
        }
        
        //controlam daca e world pack
        if ([self isWorldPack:path]) {
            [*dict setObject:path forKey:@"world_pack"];
            return;
        }
        
        //controlam restu
        for (NSString *file in files) {
            NSString *pathToGo = [path stringByAppendingPathComponent:file];
            [self analisePath:pathToGo resultDict:dict];
        }
    }
}

- (BOOL)isSkinPack:(NSString *)path{
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
    NSString *manifestPath = [path stringByAppendingPathComponent:@"manifest.json"];
    NSData *jsonData = [NSData dataWithContentsOfFile:manifestPath];
    if (jsonData) {
        NSError *readError;
        NSMutableDictionary *manifest =[NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&readError];
        if (!readError) {
            @try {
                if ([manifest[@"modules"][0][@"type"] isEqualToString:@"skin_pack"]) {
                    return YES;
                }else{
                    return NO;
                }
            } @catch (NSException *exception) {
                NSLog(@"error on manifest reading");
            } @finally {
                NSLog(@"going");
            }
        }
    }
    
    NSArray *filesForSkinPack = @[@"skins.json"];
    for (NSString *specificFile in filesForSkinPack) {
        if ([files containsObject:specificFile]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isBehaviorPack:(NSString *)path{
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
    
    NSString *manifestPath = [path stringByAppendingPathComponent:@"manifest.json"];
    NSData *jsonData = [NSData dataWithContentsOfFile:manifestPath];
    if (jsonData) {
        NSError *readError;
        NSMutableDictionary *manifest =[NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&readError];
        if (!readError) {
            @try {
                if ([manifest[@"modules"][0][@"type"] isEqualToString:@"data"]) {
                    return YES;
                }else{
                    return NO;
                }
            } @catch (NSException *exception) {
                NSLog(@"error on manifest reading");
            } @finally {
                NSLog(@"going");
            }
        }
    }
    
    NSArray *filesForBehaviorPack = @[@"entities", @"items", @"loot_tables", @"recipes", @"scripts", @"spawn_rules", @"trading"];
    for (NSString *specificFile in filesForBehaviorPack) {
        if ([files containsObject:specificFile]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isResourcePack:(NSString *)path{
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
    
    NSString *manifestPath = [path stringByAppendingPathComponent:@"manifest.json"];
    NSData *jsonData = [NSData dataWithContentsOfFile:manifestPath];
    if (jsonData) {
        NSError *readError;
        NSMutableDictionary *manifest =[NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&readError];
        if (!readError) {
            @try {
                if ([manifest[@"modules"][0][@"type"] isEqualToString:@"resources"]) {
                    return YES;
                }else{
                    return NO;
                }
            } @catch (NSException *exception) {
                NSLog(@"error on manifest reading");
            } @finally {
                NSLog(@"going");
            }
        }
    }
   NSArray *filesForResourcePack = @[@"animation_controllers", @"animations", @"attachables", @"biomes_client.json", @"blocks.json", @"entity", @"models", @"particles", @"render_controllers", @"sounds", @"sounds.json", @"textures", @"ui"];
    for (NSString *specificFile in filesForResourcePack) {
        if ([files containsObject:specificFile]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isWorldPack:(NSString *)path{
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
    
    NSString *manifestPath = [path stringByAppendingPathComponent:@"manifest.json"];
    NSData *jsonData = [NSData dataWithContentsOfFile:manifestPath];
    if (jsonData) {
        NSError *readError;
        NSMutableDictionary *manifest =[NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&readError];
        if (!readError) {
            @try {
                if ([manifest[@"modules"][0][@"type"] isEqualToString:@"world_template"]) {
                    return YES;
                }else{
                    return NO;
                }
            } @catch (NSException *exception) {
                NSLog(@"error on manifest reading");
            } @finally {
                NSLog(@"going");
            }
        }
    }
    
    NSArray *filesForBehaviorPack = @[@"level.dat", @"db"];
    for (NSString *specificFile in filesForBehaviorPack) {
        if ([files containsObject:specificFile]) {
            return YES;
        }
    }
    return NO;
}

@end
