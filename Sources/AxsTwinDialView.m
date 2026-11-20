#import "AxsTwinDialView.h"
#import "AxsTwinDialConfig.h"
#import "AxsTwinDialMedia.h"
#import "AxsTwinDialWeather.h"
#import "AxsTwinDialArc.h"
#import "AxsTwinDialPaths.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreLocation/CoreLocation.h>
#import <math.h>

static id axs_twindial_setting(NSString *key, id fallback) {
    return [[AxsTwinDialConfig axs_twindial_shared] axs_twindial_valueForKey:key defaultValue:fallback];
}
static CGFloat axs_twindial_number(NSString *key, CGFloat fallback, CGFloat low, CGFloat high) {
    id n = axs_twindial_setting(key, @(fallback));
    double value = [n isKindOfClass:NSNumber.class] ? [n doubleValue] : fallback;
    return isfinite(value) ? fmax(low, fmin(high, value)) : fallback;
}
static UIColor *axs_twindial_color(NSString *key) {
    id base = axs_twindial_setting(@"textColor", @"F0FAFF");
    id v = key ? axs_twindial_setting(key, base) : base;
    unsigned int rgb = 0;
    if (![v isKindOfClass:NSString.class] || [v length] != 6) return UIColor.whiteColor;
    NSScanner *scan = [NSScanner scannerWithString:v];
    if (![scan scanHexInt:&rgb] || !scan.isAtEnd) return UIColor.whiteColor;
    return [UIColor colorWithRed:((rgb >> 16) & 255)/255.0 green:((rgb >> 8) & 255)/255.0 blue:(rgb & 255)/255.0 alpha:1];
}
static UILabel *axs_twindial_label(void) {
    UILabel *label = [UILabel new];
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.78;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

@interface AxsTwinDialView () <UIGestureRecognizerDelegate, CLLocationManagerDelegate>
@property(nonatomic,strong) UIView *player, *weather;
@property(nonatomic,strong) UIImageView *playerArt, *weatherArt;
@property(nonatomic,strong) UIImage *playImage, *pauseImage;
@property(nonatomic,strong) CAShapeLayer *bridge;
@property(nonatomic,strong) AxsTwinDialArc *lyricTop, *lyricBottom, *weatherTop, *weatherBottom;
@property(nonatomic,strong) UILabel *footer, *weatherMessage, *weatherAlert;
@property(nonatomic,strong) UIButton *previous, *toggle, *next;
@property(nonatomic,strong) NSData *imageData;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,copy) NSString *city, *locationStatus;
@property(nonatomic,strong) CLLocationManager *locationManager;
@property(nonatomic,strong) CLGeocoder *geocoder;
@property(nonatomic,strong) CLLocation *lastPlace;
@property(nonatomic) NSUInteger locationGeneration;
@property(nonatomic) BOOL autoLocation;
@property(nonatomic,strong) NSDictionary *weatherData;
@property(nonatomic) NSUInteger weatherGeneration, mediaGeneration, feedbackGeneration;
@property(nonatomic) BOOL running, mediaPending, weatherPending, volumeTracking, feedbackActive;
@property(nonatomic) NSTimeInterval nextWeather, mediaStarted, lastVolumeWrite;
@property(nonatomic) float volumeBase;
@property(nonatomic) CGFloat period, leftScale, rightScale, topX, topY;
@property(nonatomic,copy) NSString *lrcName, *lrcText;
@property(nonatomic,copy) NSArray<NSArray *> *lrcRows;
@property(nonatomic) BOOL demoLyrics;
@end

@implementation AxsTwinDialView
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.accessibilityIdentifier = @"AxsTwinDialDesktop";
    _bridge = [CAShapeLayer layer];
    _bridge.fillColor = [UIColor colorWithRed:.07 green:.16 blue:.23 alpha:1].CGColor;
    _bridge.strokeColor = [UIColor colorWithRed:.48 green:.76 blue:.86 alpha:.45].CGColor;
    _bridge.lineWidth = 1;
    [self.layer addSublayer:_bridge];
    _player = [UIView new]; _weather = [UIView new];
    _playerArt = [UIImageView new]; _weatherArt = [UIImageView new];
    for (UIView *disc in @[_player, _weather]) {
        disc.clipsToBounds = YES;
        disc.backgroundColor = [UIColor colorWithRed:.07 green:.16 blue:.23 alpha:1];
        disc.layer.borderWidth = 1;
        disc.layer.borderColor = _bridge.strokeColor;
        [self addSubview:disc];
    }
    [_player addSubview:_playerArt]; [_weather addSubview:_weatherArt];
    for (UIImageView *art in @[_playerArt, _weatherArt]) {
        art.contentMode = UIViewContentModeScaleAspectFill;
        art.layer.masksToBounds = YES;
        art.userInteractionEnabled = NO;
    }
    // The dim layer stays fixed; only the underlying artwork turns.
    for (UIView *disc in @[_player, _weather]) {
        UIView *shade = [[UIView alloc] initWithFrame:disc.bounds];
        shade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        shade.backgroundColor = [UIColor colorWithWhite:.015 alpha:.33];
        shade.userInteractionEnabled = NO;
        [disc addSubview:shade];
    }
    _lyricTop = [AxsTwinDialArc new]; _lyricBottom = [AxsTwinDialArc new]; _lyricBottom.bottom = YES;
    _lyricTop.axs_twindial_separateBands = _lyricBottom.axs_twindial_separateBands = YES;
    [_player addSubview:_lyricTop]; [_player addSubview:_lyricBottom];
    _footer = axs_twindial_label(); _footer.userInteractionEnabled = NO;
    [_player addSubview:_footer];
    _playImage = [self axs_twindial_image:@"next" fallback:@"play.fill"];
    _pauseImage = [self axs_twindial_image:@"pause" fallback:@"pause.fill"];
    _previous = [self axs_twindial_button:[self axs_twindial_image:@"previous" fallback:@"backward.fill"] name:@"上一首" command:AxsTwinDialCommandPrevious];
    _toggle = [self axs_twindial_button:_playImage name:@"播放" command:AxsTwinDialCommandToggle];
    _next = [self axs_twindial_button:[self axs_twindial_image:@"next" fallback:@"forward.fill"] name:@"下一首" command:AxsTwinDialCommandNext];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(axs_twindial_pan:)];
    pan.maximumNumberOfTouches = 1;
    pan.delegate = self;
    [_player addGestureRecognizer:pan];
    _weatherTop = [AxsTwinDialArc new]; _weatherBottom = [AxsTwinDialArc new]; _weatherBottom.bottom = YES;
    [_weather addSubview:_weatherTop]; [_weather addSubview:_weatherBottom];
    _weatherMessage = axs_twindial_label(); _weatherMessage.text = @"平安·喜乐";
    _weatherAlert = axs_twindial_label();
    [_weather addSubview:_weatherMessage]; [_weather addSubview:_weatherAlert];
    [self axs_twindial_reloadStyle];
    return self;
}

- (UIImage *)axs_twindial_image:(NSString *)name fallback:(NSString *)symbol {
    NSString *file = [@"/Library/Application Support/AxsTwinDialResources.bundle" stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
    UIImage *img = [UIImage imageWithContentsOfFile:axs_twindial_resourcePath(file)];
    if (!img) return [UIImage systemImageNamed:symbol];
    if (img.CGImage && CGImageGetWidth(img.CGImage) > 0)
        img = [UIImage imageWithCGImage:img.CGImage scale:CGImageGetWidth(img.CGImage)/28.0 orientation:UIImageOrientationUp];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (UIButton *)axs_twindial_button:(UIImage *)image name:(NSString *)name command:(AxsTwinDialCommand)command {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:image forState:UIControlStateNormal];
    // The PNG is already normalized to 28 pt; keep the full button as the hit area.
    button.imageView.contentMode = UIViewContentModeScaleAspectFit;
    button.tag = command;
    button.accessibilityLabel = name;
    [button addTarget:self action:@selector(axs_twindial_pressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.player addSubview:button];
    return button;
}

- (void)axs_twindial_reloadStyle {
    self.leftScale = axs_twindial_number(@"playerScale", 1, .72, 1.34);
    self.rightScale = axs_twindial_number(@"weatherScale", 1, .72, 1.34);
    self.topX = axs_twindial_number(@"topX", 0, -12, 12);
    self.topY = axs_twindial_number(@"topY", 0, -12, 12);
    CGFloat period = axs_twindial_number(@"period", 18, 0, 60);
    BOOL newPeriod = self.period != period;
    self.period = period;
    UIColor *ink = axs_twindial_color(nil);
    self.lyricTop.ink = axs_twindial_color(@"inkLyrics");
    self.lyricBottom.ink = axs_twindial_color(@"inkTrack");
    self.weatherTop.ink = axs_twindial_color(@"inkForecast");
    self.weatherBottom.ink = axs_twindial_color(@"inkPlace");
    self.weatherMessage.textColor = axs_twindial_color(@"inkMessage");
    self.weatherAlert.textColor = axs_twindial_color(@"inkAlert");
    self.footer.textColor = ink;
    for (UIView *v in @[self.previous,self.toggle,self.next]) v.tintColor = ink;
    self.demoLyrics = [axs_twindial_setting(@"demoLyrics", @NO) isEqual:@YES];
    id local = axs_twindial_setting(@"localLRC", nil);
    NSDictionary *lrc = [local isKindOfClass:NSDictionary.class] ? local : nil;
    NSString *text = [lrc[@"text"] isKindOfClass:NSString.class] ? lrc[@"text"] : @"";
    NSString *name = [lrc[@"name"] isKindOfClass:NSString.class] ? lrc[@"name"] : @"";
    if (![self.lrcText isEqualToString:text] || ![self.lrcName isEqualToString:name]) {
        self.lrcName = name; self.lrcText = text;
        self.lrcRows = [self axs_twindial_parseLyrics:text];
        self.lyricTop.text = self.demoLyrics ? @"示例 · 把夜色交给海风" : @"未导入匹配歌词";
    }
    if (self.running) [self axs_twindial_refreshMedia];
    if (!self.lyricBottom.text.length) self.lyricBottom.text = @"暂无曲目";
    self.toggle.backgroundColor = [ink colorWithAlphaComponent:.16];
    id image = axs_twindial_setting(@"artwork", nil);
    NSData *valid = [image isKindOfClass:NSData.class] && [image length] <= 350000 ? image : nil;
    if (valid != self.imageData && ![valid isEqualToData:self.imageData]) {
        self.imageData = valid;
        UIImage *art = valid ? [UIImage imageWithData:valid] : nil;
        self.playerArt.image = art; self.weatherArt.image = art;
    }
    if (!self.playerArt.image) self.playerArt.image = [self axs_twindial_defaultArt:NO];
    if (!self.weatherArt.image) self.weatherArt.image = [self axs_twindial_defaultArt:YES];
    id autoValue = axs_twindial_setting(@"autoLocation", @YES);
    BOOL automatic = [autoValue isKindOfClass:NSNumber.class] ? [autoValue boolValue] : YES;
    if (automatic != self.autoLocation) {
        self.autoLocation = automatic;
        [self axs_twindial_stopLocation];
        self.locationStatus = nil;
        [self axs_twindial_setWeatherCity:@""];
        if (automatic && self.running) [self axs_twindial_startLocation];
    }
    if (!automatic) {
        id rawCity = axs_twindial_setting(@"city", @"");
        [self axs_twindial_setWeatherCity:[rawCity isKindOfClass:NSString.class] ? rawCity : @""];
    }
    if (newPeriod && self.running) [self axs_twindial_spin:YES];
    if (self.running) [self axs_twindial_checkWeather];
    [self setNeedsLayout];
}

- (UIImage *)axs_twindial_defaultArt:(BOOL)weather {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(240, 240)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextRef g = context.CGContext;
        UIColor *accent = weather ? [UIColor colorWithRed:.19 green:.64 blue:.60 alpha:1] : [UIColor colorWithRed:.26 green:.48 blue:.76 alpha:1];
        UIColor *base = [UIColor colorWithRed:.04 green:.10 blue:.20 alpha:1];
        CGColorSpaceRef s = CGColorSpaceCreateDeviceRGB();
        NSArray *colors = @[(__bridge id)accent.CGColor, (__bridge id)base.CGColor];
        CGGradientRef gradient = CGGradientCreateWithColors(s, (__bridge CFArrayRef)colors, NULL);
        CGContextDrawRadialGradient(g, gradient, CGPointMake(weather ? 166 : 70, 50), 0, CGPointMake(120, 120), 155, kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(gradient); CGColorSpaceRelease(s);
        CGContextSetStrokeColorWithColor(g, [UIColor colorWithWhite:1 alpha:.10].CGColor);
        CGContextSetLineWidth(g, .8);
        for (CGFloat radius = 28; radius < 123; radius += 9) CGContextStrokeEllipseInRect(g, CGRectMake(120-radius,120-radius,radius*2,radius*2));
    }];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = CGRectGetWidth(self.bounds), h = CGRectGetHeight(self.bounds);
    if (w < 230 || h < 180) { self.player.hidden = self.weather.hidden = self.bridge.hidden = YES; return; }
    self.player.hidden = self.weather.hidden = self.bridge.hidden = NO;
    CGFloat left = fmin(w*.40,160)*self.leftScale, right = fmin(w*.445,180)*self.rightScale;
    CGFloat gap = fmin(46, w*.115);
    CGFloat safeTop = self.safeAreaInsets.top;
    if (h-safeTop < 80) { self.player.hidden = self.weather.hidden = self.bridge.hidden = YES; return; }
    CGFloat fit = fmin(1, (w-56-gap)/(left+right));
    fit = fmin(fit,(h-safeTop-32)/fmax(left,right));
    left *= fit; right *= fit;
    CGFloat x = (w-left-right-gap)/2 + self.topX, lx = x+left/2, rx = x+left+gap+right/2;
    CGFloat cy = safeTop + 16 + self.topY + fmax(left,right)/2;
    [self axs_twindial_disc:self.player art:self.playerArt size:left center:CGPointMake(lx,cy)];
    [self axs_twindial_disc:self.weather art:self.weatherArt size:right center:CGPointMake(rx,cy)];
    CGFloat a = lx+left/2-9, b = rx-right/2+9, d = b-a;
    UIBezierPath *shape = [UIBezierPath bezierPath];
    [shape moveToPoint:CGPointMake(a,cy-10)];
    [shape addCurveToPoint:CGPointMake(b,cy-10) controlPoint1:CGPointMake(a+d*.45,cy-29) controlPoint2:CGPointMake(a+d*.55,cy+7)];
    [shape addLineToPoint:CGPointMake(b,cy+10)];
    [shape addCurveToPoint:CGPointMake(a,cy+10) controlPoint1:CGPointMake(a+d*.55,cy+27) controlPoint2:CGPointMake(a+d*.45,cy-9)];
    [shape closePath];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.bridge.frame = self.bounds; self.bridge.path = shape.CGPath;
    [CATransaction commit];
    self.lyricTop.frame = self.lyricBottom.frame = self.player.bounds;
    self.weatherTop.frame = self.weatherBottom.frame = self.weather.bounds;
    [self axs_twindial_label:self.footer diameter:left y:.68 font:.075 weight:UIFontWeightMedium];
    CGFloat tap = fmin(48,left*.30);
    NSArray<UIButton *> *buttons = @[self.previous,self.toggle,self.next];
    for (NSUInteger i = 0; i < buttons.count; ++i) {
        UIButton *button = buttons[i];
        button.frame = CGRectMake(left*(.5+(.29*((NSInteger)i-1)))-tap/2, left*.50-tap/2, tap,tap);
        button.layer.cornerRadius = tap/2;
        [button setPreferredSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:fmax(12,left*(i == 1 ? .16 : .12)) weight:UIImageSymbolWeightMedium] forImageInState:UIControlStateNormal];
    }
    [self axs_twindial_label:self.weatherMessage diameter:right y:.48 font:.154 weight:UIFontWeightBold];
    [self axs_twindial_label:self.weatherAlert diameter:right y:.627 font:.078 weight:UIFontWeightMedium];
}

- (void)axs_twindial_disc:(UIView *)disc art:(UIImageView *)art size:(CGFloat)size center:(CGPoint)center {
    disc.bounds = CGRectMake(0,0,size,size); disc.center = center; disc.layer.cornerRadius = size/2;
    CGFloat coverage = size*1.43;
    art.bounds = CGRectMake(0,0,coverage,coverage);
    art.center = CGPointMake(size/2, size/2);
}

- (void)axs_twindial_label:(UILabel *)label diameter:(CGFloat)d y:(CGFloat)y font:(CGFloat)size weight:(UIFontWeight)weight {
    CGFloat width = d * (y > .70 ? .78 : .81), height = d*size*1.24;
    label.frame = CGRectMake((d-width)/2,d*y-height/2,width,height);
    label.font = [UIFont systemFontOfSize:fmax(8,d*size) weight:weight];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.running || self.hidden || self.player.hidden || self.alpha < .01) return nil;
    CGPoint p = [self convertPoint:point toView:self.player];
    CGFloat r = CGRectGetWidth(self.player.bounds)/2;
    if (hypot(p.x-r,p.y-r) > r) return nil;
    return [self.player hitTest:p withEvent:event];
}

- (void)axs_twindial_spin:(BOOL)start {
    NSUInteger index = 0;
    for (UIImageView *art in @[self.playerArt,self.weatherArt]) {
        CALayer *layer = art.layer;
        [layer removeAnimationForKey:@"AxsTwinDialArtworkSpin"];
        if (start && self.period > 0 && !UIAccessibilityIsReduceMotionEnabled()) {
            CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
            animation.fromValue = @0; animation.toValue = @(index ? -2*M_PI : 2*M_PI);
            animation.duration = fmax(2,self.period); animation.repeatCount = HUGE_VALF;
            [layer addAnimation:animation forKey:@"AxsTwinDialArtworkSpin"];
        }
        index++;
    }
}

- (void)axs_twindial_setRunning:(BOOL)running {
    if (_running == running) return;
    _running = running;
    if (self.autoLocation) {
        if (running) [self axs_twindial_startLocation];
        else [self axs_twindial_stopLocation];
    }
    [self axs_twindial_spin:running];
    if (running) {
        __weak typeof(self) weakSelf = self;
        self.timer = [NSTimer timerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) {
            [weakSelf axs_twindial_refreshMedia]; [weakSelf axs_twindial_checkWeather];
        }];
        [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
        [self axs_twindial_refreshMedia]; [self axs_twindial_checkWeather];
    } else {
        [self.timer invalidate]; self.timer = nil;
        self.mediaGeneration++; self.mediaPending = NO;
        self.weatherGeneration++; self.weatherPending = NO;
        self.volumeTracking = NO; self.feedbackGeneration++; self.feedbackActive = NO;
        self.footer.text = @"";
    }
}

- (void)dealloc { [_timer invalidate]; }

- (NSArray<NSArray *> *)axs_twindial_parseLyrics:(NSString *)text {
    if (!text.length || text.length > 65536) return @[];
    NSRegularExpression *tag = [NSRegularExpression regularExpressionWithPattern:@"\\[([0-9]{1,3}):([0-5][0-9])(?:[.:]([0-9]{1,3}))?\\]" options:0 error:NULL];
    NSRegularExpression *offset = [NSRegularExpression regularExpressionWithPattern:@"^\\[offset:([+-]?[0-9]{1,6})\\]$" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSMutableArray<NSArray *> *rows = [NSMutableArray array];
    __block double correction = 0;
    [text enumerateLinesUsingBlock:^(NSString *raw, BOOL *stop) {
        NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([line hasPrefix:@"\uFEFF"]) line = [line substringFromIndex:1];
        NSRange all = NSMakeRange(0,line.length);
        NSTextCheckingResult *shift = [offset firstMatchInString:line options:0 range:all];
        if (shift) { correction = [line substringWithRange:[shift rangeAtIndex:1]].doubleValue/1000.0; return; }
        NSArray<NSTextCheckingResult *> *tags = [tag matchesInString:line options:0 range:all];
        NSUInteger end = 0, count = 0;
        for (NSTextCheckingResult *t in tags) {
            if (t.range.location != end || count == 32) break;
            end = NSMaxRange(t.range); count++;
        }
        if (!count) return;
        NSString *content = [[line substringFromIndex:end] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (content.length > 256) content = [content substringToIndex:[content rangeOfComposedCharacterSequenceAtIndex:255].location];
        for (NSUInteger i=0;i<count;i++) {
            NSTextCheckingResult *t = tags[i];
            double seconds = [line substringWithRange:[t rangeAtIndex:1]].doubleValue*60 + [line substringWithRange:[t rangeAtIndex:2]].doubleValue;
            NSRange frac = [t rangeAtIndex:3];
            if (frac.location != NSNotFound) seconds += [line substringWithRange:frac].doubleValue/pow(10,frac.length);
            [rows addObject:@[@(seconds),content]];
            if (rows.count == 1200) { *stop = YES; break; }
        }
    }];
    [rows sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] compare:b[0]]; }];
    if (correction) for (NSUInteger i=0;i<rows.count;i++) rows[i] = @[@([rows[i][0] doubleValue]-correction), rows[i][1]];
    return [rows copy];
}

- (void)axs_twindial_updateLyrics:(NSDictionary *)info title:(NSString *)title artist:(NSString *)artist {
    NSString *fallback = self.demoLyrics ? @"示例 · 把夜色交给海风" : @"未导入匹配歌词";
    NSString *name = [[NSString stringWithFormat:@"%@ - %@",artist,title] precomposedStringWithCanonicalMapping];
    if (!artist.length || !title.length || ![name isEqualToString:self.lrcName.precomposedStringWithCanonicalMapping] || !self.lrcRows.count) { self.lyricTop.text = fallback; return; }
    id progress = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"];
    if (![progress isKindOfClass:NSNumber.class] || !isfinite([progress doubleValue]) || [progress doubleValue]<0) { self.lyricTop.text = @"播放器未提供进度"; return; }
    double elapsed = [progress doubleValue];
    id timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"], rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
    if ([timestamp isKindOfClass:NSDate.class] && [rate isKindOfClass:NSNumber.class]) {
        double extra = -[timestamp timeIntervalSinceNow], speed = [rate doubleValue];
        if (isfinite(extra) && extra > 0 && extra < 86400 && isfinite(speed) && speed > 0 && speed <= 4) elapsed += extra*speed;
    }
    NSUInteger lo=0, hi=self.lrcRows.count;
    while (lo<hi) { NSUInteger m=lo+(hi-lo)/2; if ([self.lrcRows[m][0] doubleValue]<=elapsed) lo=m+1; else hi=m; }
    NSString *line = lo ? self.lrcRows[lo-1][1] : @"";
    self.lyricTop.text = line.length ? line : @"♪";
}

- (void)axs_twindial_refreshMedia {
    if (!self.running) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (self.mediaPending && now-self.mediaStarted < 8) return;
    self.mediaPending = YES; self.mediaStarted = now;
    NSUInteger token = ++self.mediaGeneration;
    __weak typeof(self) weakSelf = self;
    axs_twindial_nowPlaying(^(NSDictionary *info, BOOL playing) {
        AxsTwinDialView *view = weakSelf;
        if (!view.running || token != view.mediaGeneration) return;
        view.mediaPending = NO;
        id title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
        id artist = info[@"kMRMediaRemoteNowPlayingInfoArtist"];
        NSString *name = [title isKindOfClass:NSString.class] ? title : @"";
        NSString *by = [artist isKindOfClass:NSString.class] ? artist : @"";
        view.lyricBottom.text = name.length ? (by.length ? [NSString stringWithFormat:@"%@ · %@",name,by] : name) : (by.length ? by : @"暂无曲目");
        view.lyricBottom.accessibilityLabel = view.lyricBottom.text;
        [view axs_twindial_updateLyrics:info title:name artist:by];
        [view.toggle setImage:playing ? view.pauseImage : view.playImage forState:UIControlStateNormal];
        view.toggle.accessibilityLabel = playing ? @"暂停" : @"播放";
    });
}

- (void)axs_twindial_pressed:(UIButton *)button {
    if (!self.running) return;
    if (!axs_twindial_sendCommand((AxsTwinDialCommand)button.tag)) [self axs_twindial_feedback:@"暂无可控媒体" restore:YES];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.35*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf axs_twindial_refreshMedia];
    });
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    CGPoint velocity = [(UIPanGestureRecognizer *)recognizer velocityInView:self.player];
    return self.running && fabs(velocity.y) > fabs(velocity.x)*1.25;
}

- (void)axs_twindial_pan:(UIPanGestureRecognizer *)pan {
    if (!self.running) return;
    if (pan.state == UIGestureRecognizerStateBegan) {
        float volume = 0;
        self.volumeTracking = axs_twindial_getVolume(&volume);
        self.volumeBase = fmaxf(0,fminf(1,volume)); self.lastVolumeWrite = 0;
        if (!self.volumeTracking) { [self axs_twindial_feedback:@"此输出不支持调音量" restore:YES]; return; }
    }
    if (!self.volumeTracking) return;
    if (pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed) {
        self.volumeTracking = NO;
        [self axs_twindial_feedback:self.footer.text restore:YES]; return;
    }
    BOOL end = pan.state == UIGestureRecognizerStateEnded;
    NSTimeInterval t = NSProcessInfo.processInfo.systemUptime;
    if (!end && t-self.lastVolumeWrite < .08) return;
    self.lastVolumeWrite = t;
    float value = fmaxf(0,fminf(1,self.volumeBase - [pan translationInView:self.player].y/155.0));
    if (!axs_twindial_setVolume(value)) {
        self.volumeTracking = NO;
        [self axs_twindial_feedback:@"此输出不支持调音量" restore:YES]; return;
    }
    self.volumeTracking = !end;
    float observed = value;
    if (end) axs_twindial_getVolume(&observed);
    [self axs_twindial_feedback:[NSString stringWithFormat:@"音量 %.0f%%",fmaxf(0,fminf(1,observed))*100] restore:end];
}

- (void)axs_twindial_feedback:(NSString *)text restore:(BOOL)restore {
    self.footer.text = text; self.feedbackActive = YES;
    NSUInteger token = ++self.feedbackGeneration;
    if (!restore) return;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.15*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AxsTwinDialView *view = weakSelf;
        if (token != view.feedbackGeneration || view.volumeTracking) return;
        view.feedbackActive = NO; view.footer.text = @"";
    });
}

- (void)axs_twindial_setWeatherCity:(NSString *)city {
    city = [city stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (city.length > 159) city = @"";
    if ([city isEqualToString:self.city]) return;
    self.city = city;
    self.weatherGeneration++; self.weatherPending = NO;
    self.nextWeather = 0; self.weatherData = nil;
    [self axs_twindial_updateWeather:nil];
}

- (void)axs_twindial_stopLocation {
    self.locationGeneration++;
    [self.geocoder cancelGeocode]; self.geocoder = nil;
    self.lastPlace = nil;
    [self.locationManager stopUpdatingLocation];
    self.locationManager.delegate = nil; self.locationManager = nil;
}

- (void)axs_twindial_startLocation {
    if (self.locationManager || !self.running || !self.autoLocation) return;
    self.locationStatus = @"等待定位";
    self.locationManager = [CLLocationManager new];
    self.locationManager.desiredAccuracy = kCLLocationAccuracyKilometer;
    self.locationManager.distanceFilter = 1500;
    self.locationManager.delegate = self;
    [self locationManagerDidChangeAuthorization:self.locationManager];
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if (manager != self.locationManager || !self.running || !self.autoLocation) return;
    CLAuthorizationStatus state = manager.authorizationStatus;
    if (state == kCLAuthorizationStatusAuthorizedAlways || state == kCLAuthorizationStatusAuthorizedWhenInUse) {
        [manager startUpdatingLocation];
    } else {
        [manager stopUpdatingLocation];
        self.locationGeneration++; [self.geocoder cancelGeocode]; self.geocoder = nil; self.lastPlace = nil;
        self.locationStatus = state == kCLAuthorizationStatusNotDetermined ? @"桌面定位未获授权" : @"定位不可用";
        [self axs_twindial_setWeatherCity:@""];
        [self axs_twindial_updateWeather:nil];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    if (manager != self.locationManager || !self.running || !self.autoLocation) return;
    if (manager.authorizationStatus != kCLAuthorizationStatusAuthorizedAlways && manager.authorizationStatus != kCLAuthorizationStatusAuthorizedWhenInUse) return;
    CLLocation *point = locations.lastObject;
    if (!point || !CLLocationCoordinate2DIsValid(point.coordinate) || point.horizontalAccuracy < 0 || point.horizontalAccuracy > 30000 || fabs(point.timestamp.timeIntervalSinceNow)>600) return;
    if (self.lastPlace && [self.lastPlace distanceFromLocation:point] < 1500) return;
    self.lastPlace = point;
    NSUInteger generation = ++self.locationGeneration;
    [self.geocoder cancelGeocode]; self.geocoder = [CLGeocoder new];
    NSString *coordinates = [NSString stringWithFormat:@"%.2f,%.2f",point.coordinate.latitude,point.coordinate.longitude];
    NSString *suffix = [@"@" stringByAppendingString:coordinates];
    if (![self.city hasSuffix:suffix]) {
        self.locationStatus = @"正在更新位置";
        [self axs_twindial_setWeatherCity:@""];
    }
    __weak typeof(self) weakSelf = self;
    void (^apply)(NSString *) = ^(NSString *label) {
        AxsTwinDialView *view = weakSelf;
        if (!view.running || !view.autoLocation || generation != view.locationGeneration) return;
        [view axs_twindial_setWeatherCity:[NSString stringWithFormat:@"%@@%@",label.length ? label : @"当前位置",coordinates]];
        [view axs_twindial_checkWeather];
    };
    [self.geocoder reverseGeocodeLocation:point completionHandler:^(NSArray<CLPlacemark *> *marks, NSError *error) {
        if (error) return;
        CLPlacemark *mark = marks.firstObject;
        dispatch_async(dispatch_get_main_queue(), ^{ apply(mark.locality ?: mark.subAdministrativeArea ?: mark.administrativeArea); });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,6*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        AxsTwinDialView *view = weakSelf;
        if (![view.city hasSuffix:[@"@" stringByAppendingString:coordinates]]) apply(nil);
    });
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if (manager != self.locationManager || !self.running || !self.autoLocation) return;
    if (error.code == kCLErrorDenied) [self locationManagerDidChangeAuthorization:manager];
    else if (!self.city.length) { self.locationStatus = @"暂未取得位置"; [self axs_twindial_updateWeather:nil]; }
}

- (void)axs_twindial_checkWeather {
    if (!self.running || !self.city.length || self.weatherPending || (self.autoLocation && !self.lastPlace)) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now < self.nextWeather) return;
    self.weatherPending = YES;
    self.nextWeather = now + 90;
    NSUInteger token = ++self.weatherGeneration;
    __weak typeof(self) weakSelf = self;
    axs_twindial_fetchWeather(self.city, ^(NSDictionary<NSString *, NSString *> *data, NSString *error) {
        AxsTwinDialView *view = weakSelf;
        if (!view.running || token != view.weatherGeneration) return;
        view.weatherPending = NO;
        view.nextWeather = NSProcessInfo.processInfo.systemUptime + (data ? 900 : 180);
        if (data) view.weatherData = data;
        [view axs_twindial_updateWeather:error];
    });
}

- (void)axs_twindial_updateWeather:(NSString *)error {
    NSDictionary *data = self.weatherData;
    NSString *condition = data[@"condition"], *range = data[@"range"];
    NSString *location = data[@"location"] ?: (self.autoLocation ? @"" : self.city), *rain = data[@"rain"];
    self.weatherTop.text = condition.length ? (range.length ? [NSString stringWithFormat:@"%@ · %@",condition,range] : condition) : (self.city.length ? (error ?: @"正在获取") : (self.autoLocation ? (self.locationStatus ?: @"等待定位") : @"请设置城市"));
    self.weatherBottom.text = rain.length ? [NSString stringWithFormat:@"%@ · %@",location ?: @"",rain] : (location ?: @"");
    self.weatherAlert.text = data[@"alert"] ?: (data && error ? @"数据暂未刷新" : @"");
}
@end
