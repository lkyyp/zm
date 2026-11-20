#import "AxsTwinDialRootListController.h"
#import "AxsTwinDialPreferences.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import "AxsTwinDialSliderCell.h"

#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface AxsTwinDialRootListController () <AxsTwinDialSliderCellHandler, PHPickerViewControllerDelegate, UIDocumentPickerDelegate>
@end

@implementation AxsTwinDialRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"AxsTwinDialRoot"
                                                           target:self] mutableCopy];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"自定义底图" target:self
                     set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [self axs_twindial_addButton:@"从相册选一张背景" action:@selector(axs_twindial_pick:) to:items];
        [self axs_twindial_addButton:@"恢复默认背景" action:@selector(axs_twindial_resetArt:) to:items];
        [self axs_twindial_addButton:@"分行设置文字颜色" action:@selector(axs_twindial_pickInk:) to:items];
        [self axs_twindial_addButton:@"精确输入整体位置" action:@selector(axs_twindial_exactPosition:) to:items];
        [self axs_twindial_addButton:@"导入 LRC 歌词" action:@selector(axs_twindial_selectLyrics:) to:items];
        [self axs_twindial_addButton:@"LRC 歌词命名说明" action:@selector(axs_twindial_importLyrics:) to:items];
        [self axs_twindial_addButton:@"自动定位帮助" action:@selector(axs_twindial_locationHelp:) to:items];
        [self axs_twindial_addButton:@"设置天气城市" action:@selector(axs_twindial_pickCity:) to:items];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"关于我们" target:self
                     set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [self axs_twindial_addButton:@"Sileo 越狱源" action:@selector(axs_twindial_openRepository:) to:items];
        [self axs_twindial_addButton:@"TG分享频道" action:@selector(axs_twindial_openTelegram:) to:items];
        [self axs_twindial_addButton:@"QQ交流群组" action:@selector(axs_twindial_openQQ:) to:items];
        _specifiers = items;
    }
    return _specifiers;
}

- (void)axs_twindial_addButton:(NSString *)title action:(SEL)action to:(NSMutableArray *)items {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:title target:self
                          set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    item.buttonAction = action;
    [items addObject:item];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return nil;
    return axs_twindial_readPreferences()[key] ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) return;
    NSError *error = nil;
    if (!axs_twindial_writePreference(key, value, &error)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置未保存"
            message:error.localizedDescription ?: @"请检查配置文件路径和写入权限。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [self reloadSpecifiers];
    }
}

- (void)axs_twindial_note:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)axs_twindial_pick:(id)sender {
    PHPickerConfiguration *config = [PHPickerConfiguration new];
    config.filter = PHPickerFilter.imagesFilter;
    config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    NSItemProvider *provider = results.firstObject.itemProvider;
    [picker dismissViewControllerAnimated:YES completion:^{
        if (!provider) return;
        __weak typeof(self) weakSelf = self;
        [provider loadFileRepresentationForTypeIdentifier:UTTypeImage.identifier completionHandler:^(NSURL *url, NSError *error) {
            NSData *jpg = nil;
            if (url && !error) {
                CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceShouldCache:@NO});
                NSDictionary *opts = @{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                                       (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,
                                       (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@620};
                CGImageRef thumb = source ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)opts) : NULL;
                if (thumb) { jpg = UIImageJPEGRepresentation([UIImage imageWithCGImage:thumb], .82); CGImageRelease(thumb); }
                if (source) CFRelease(source);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                AxsTwinDialRootListController *owner = weakSelf;
                if (!owner.viewIfLoaded.window) return;
                NSError *writeError = nil;
                if (!jpg.length || jpg.length > 350000 || !axs_twindial_writePreference(@"artwork", jpg, &writeError))
                    [owner axs_twindial_note:@"背景未保存" message:writeError.localizedDescription ?: @"这张图片无法导入，请选另一张。"];
                else [owner axs_twindial_note:@"背景已保存" message:@"返回桌面查看。"];
            });
        }];
    }];
}

- (void)axs_twindial_resetArt:(id)sender {
    NSError *error = nil;
    if (!axs_twindial_writePreference(@"artwork", nil, &error))
        [self axs_twindial_note:@"恢复失败" message:error.localizedDescription];
    else [self axs_twindial_note:@"已恢复默认背景" message:nil];
}

- (void)axs_twindial_pickInk:(id)sender {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"文字颜色" message:nil preferredStyle:UIAlertControllerStyleAlert];
    NSArray *rows = @[@[@"默认颜色",@"textColor"], @[@"左上 · 歌词",@"inkLyrics"], @[@"左下 · 曲名和歌手",@"inkTrack"], @[@"右上 · 天气和温度",@"inkForecast"], @[@"右中 · 横排文字",@"inkMessage"], @[@"右下 · 城市和降水",@"inkPlace"], @[@"右中下 · 补充信息",@"inkAlert"]];
    __weak typeof(self) weakSelf = self;
    for (NSArray *row in rows) [menu addAction:[UIAlertAction actionWithTitle:row[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [weakSelf axs_twindial_edit:row[1] title:row[0] mode:0]; });
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)axs_twindial_locationHelp:(id)sender {
    [self axs_twindial_note:@"开启自动定位" message:@"1. 设置 → 隐私与安全性 → 定位服务，开启总开关。\n2. 回桌面双环设置，打开‘天气跟随当前位置’。\n3. 回首页等待定位。若仍提示‘桌面定位未获授权’，当前系统未给桌面宿主权限；天气 App 的授权不会转给插件。此时可关闭跟随并手填城市。"];
}

- (void)axs_twindial_importLyrics:(id)sender {
    [self axs_twindial_note:@"LRC 命名" message:@"准备带时间戳的 UTF‑8 歌词文件，文件名为‘歌手 - 曲名.lrc’，与播放器显示完全一致。关闭提示后点‘导入 LRC 歌词’。"];
}

- (void)axs_twindial_selectLyrics:(id)sender {
    UTType *lrc = [UTType typeWithFilenameExtension:@"lrc"] ?: UTTypeData;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[lrc, UTTypePlainText, UTTypeData] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSNumber *size = nil;
    [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    NSString *name = url.URLByDeletingPathExtension.lastPathComponent;
    NSMutableData *bytes = nil;
    if ([url.pathExtension.lowercaseString isEqualToString:@"lrc"] && [name containsString:@" - "] && name.length <= 200 && size.unsignedLongLongValue > 0 && size.unsignedLongLongValue <= 65536) {
        NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
        bytes = [[handle readDataUpToLength:65537 error:nil] mutableCopy];
        [handle closeFile];
    }
    if (scoped) [url stopAccessingSecurityScopedResource];
    NSString *text = bytes.length <= 65536 ? [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding] : nil;
    NSError *error = nil;
    BOOL valid = text.length && [text rangeOfString:@"\\[[0-9]{1,3}:[0-5][0-9]" options:NSRegularExpressionSearch].location != NSNotFound;
    BOOL saved = valid && axs_twindial_writePreference(@"localLRC",@{@"name":name,@"text":text},&error);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if (self.viewIfLoaded.window) [self axs_twindial_note:saved ? @"歌词已保存" : @"歌词未保存" message:saved ? @"回首页播放文件名对应的歌曲。再次导入会替换当前歌词文件。" : (error.localizedDescription ?: @"请选用‘歌手 - 曲名.lrc’命名的 UTF‑8 时间轴歌词，最大 64 KB。")];
    });
}

- (void)axs_twindial_pickCity:(id)sender { [self axs_twindial_edit:@"city" title:@"天气城市" mode:1]; }
- (void)axs_twindial_exactPosition:(id)sender {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"精确输入整体位置" message:nil preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    for (NSArray *row in @[@[@"顶部横向",@"topX"],@[@"顶部纵向",@"topY"]]) [menu addAction:[UIAlertAction actionWithTitle:row[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [weakSelf axs_twindial_edit:row[1] title:row[0] mode:2]; });
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)axs_twindial_edit:(NSString *)key title:(NSString *)title mode:(NSUInteger)mode {
    NSString *message = mode == 0 ? @"输入 6 位色号，例如 F0FAFF；留空沿用默认颜色。" : mode == 1 ? @"输入城市名或纬度,经度，会发送给 Open-Meteo 查询；留空关闭天气。" : @"输入 −12 至 12 点，支持两位小数。";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        id current = axs_twindial_readPreferences()[key];
        if (mode == 2) {
            double value = [current isKindOfClass:NSNumber.class] ? [current doubleValue] : 0;
            field.text = [NSString stringWithFormat:@"%.2f",value];
            field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        } else {
            field.text = [current isKindOfClass:NSString.class] ? current : @"";
            field.placeholder = mode == 0 ? @"F0FAFF" : @"上海 / Shanghai / 31.23,121.47";
        }
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *value = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        if (mode == 0 && [value hasPrefix:@"#"]) value = [value substringFromIndex:1];
        id saved = value.length ? value : nil;
        NSCharacterSet *nonHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"] invertedSet];
        NSString *notice = nil;
        if (mode == 0 && value.length && (value.length != 6 || [value rangeOfCharacterFromSet:nonHex].location != NSNotFound)) notice = @"请输入有效的 6 位色号。";
        else if (mode == 1 && value.length > 96) notice = @"城市名或坐标太长。";
        else if (mode == 2) {
            NSString *number = [value stringByReplacingOccurrencesOfString:@"," withString:@"."];
            double n = number.doubleValue;
            if (number.length > 6 || [number rangeOfString:@"^[+-]?[0-9]{1,2}([.][0-9]{1,2})?$" options:NSRegularExpressionSearch].location == NSNotFound || n < -12 || n > 12) notice = @"位置超出范围或小数超过两位。";
            else saved = @(n);
        }
        if (!notice) {
            NSError *error = nil;
            if (!axs_twindial_writePreference(key, saved, &error)) notice = error.localizedDescription ?: @"配置不可写。";
        }
        if (notice) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 450*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [weakSelf axs_twindial_note:@"设置未保存" message:notice]; });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)axs_twindial_openURL:(NSURL *)url fallback:(NSURL *)fallback {
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (success) return;
        if (fallback) {
            [self axs_twindial_openURL:fallback fallback:nil];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法打开链接"
                message:@"请确认已安装对应应用。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }];
}

- (void)axs_twindial_openRepository:(id)sender {
    NSString *source = @"https://axs66.github.io/pro";
    // Encode the entire URL as a path component, including its own delimiters.
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                              @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    NSString *encoded = [source stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    NSURL *primary = [NSURL URLWithString:[@"sileo://source/" stringByAppendingString:encoded]];
    [self axs_twindial_openURL:primary fallback:[NSURL URLWithString:source]];
}

- (void)axs_twindial_openTelegram:(id)sender {
    [self axs_twindial_openURL:[NSURL URLWithString:@"tg://resolve?domain=wxfx8"]
                   fallback:[NSURL URLWithString:@"https://t.me/wxfx8"]];
}

- (void)axs_twindial_openQQ:(id)sender {
    [self axs_twindial_openURL:[NSURL URLWithString:@"mqqapi://card/show_pslcard?src_type=internal&version=1&uin=678055716&card_type=group&source=qrcode"] fallback:nil];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell
    forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([PSListController instancesRespondToSelector:_cmd]) {
        [super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
    }
    if ([cell isKindOfClass:[AxsTwinDialSliderCell class]]) {
        AxsTwinDialSliderCell *sliderCell = (AxsTwinDialSliderCell *)cell;
        sliderCell.handler = self;
        [sliderCell axs_twindial_reloadState];
    }
}

- (double)axs_twindial_sliderValueForSpecifier:(PSSpecifier *)specifier {
    id value = [self readPreferenceValue:specifier];
    return [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : 0.0;
}

- (void)axs_twindial_setSliderValue:(double)value specifier:(PSSpecifier *)specifier {
    double minimum = [[specifier propertyForKey:@"min"] doubleValue];
    double maximum = [[specifier propertyForKey:@"max"] doubleValue];
    if (!isfinite(minimum)) minimum = 0.0;
    if (!isfinite(maximum) || maximum <= minimum) maximum = minimum + 1.0;
    if (!isfinite(value)) value = minimum;
    [self setPreferenceValue:@(fmax(minimum, fmin(maximum, value))) specifier:specifier];
}

@end
