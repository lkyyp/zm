#import "AxsTwinDialRootListController.h"
#import "AxsTwinDialPreferences.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import "AxsTwinDialSliderCell.h"

#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface AxsTwinDialRootListController () <AxsTwinDialSliderCellHandler, PHPickerViewControllerDelegate>
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
        [self axs_twindial_addButton:@"设置文字颜色" action:@selector(axs_twindial_pickInk:) to:items];
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

- (void)axs_twindial_pickInk:(id)sender { [self axs_twindial_editField:YES]; }
- (void)axs_twindial_pickCity:(id)sender { [self axs_twindial_editField:NO]; }

- (void)axs_twindial_editField:(BOOL)ink {
    NSString *key = ink ? @"textColor" : @"city";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:ink ? @"文字颜色" : @"天气城市"
        message:ink ? @"输入 6 位色号，例如 F0FAFF；留空恢复默认。" : @"输入城市名或纬度,经度。城市名或手填坐标会发送给 Open-Meteo 查询；留空关闭天气。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        id current = axs_twindial_readPreferences()[key];
        field.text = [current isKindOfClass:NSString.class] ? current : @"";
        field.placeholder = ink ? @"F0FAFF" : @"上海 / Shanghai / 31.23,121.47";
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *value = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        if (ink && [value hasPrefix:@"#"]) value = [value substringFromIndex:1];
        NSCharacterSet *nonHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"] invertedSet];
        NSString *notice = nil;
        if (ink && value.length && (value.length != 6 || [value rangeOfCharacterFromSet:nonHex].location != NSNotFound)) notice = @"请输入有效的 6 位色号。";
        else if (value.length > 96) notice = @"城市名或坐标太长。";
        else {
            NSError *error = nil;
            if (!axs_twindial_writePreference(key, value.length ? value : nil, &error)) notice = error.localizedDescription ?: @"配置不可写。";
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
