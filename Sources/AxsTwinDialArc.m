#import "AxsTwinDialArc.h"
#import <math.h>

@implementation AxsTwinDialArc
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeRedraw;
        self.isAccessibilityElement = YES;
    }
    return self;
}
- (void)setText:(NSString *)text {
    if ((_text == text) || [_text isEqualToString:text]) return;
    _text = [text copy]; self.accessibilityLabel = _text; [self setNeedsDisplay];
}
- (void)setInk:(UIColor *)ink { _ink = ink; [self setNeedsDisplay]; }
- (void)setBottom:(BOOL)bottom { _bottom = bottom; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    if (!self.text.length) return;
    CGFloat d = MIN(self.bounds.size.width,self.bounds.size.height), r = d*.386;
    if (r < 1) return;
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds),CGRectGetMidY(self.bounds));
    CGFloat limit = r*(self.axs_twindial_separateBands ? (self.bottom ? 1.55 : 1.90) : 2.35);
    NSDictionary *attrs = @{NSFontAttributeName:[UIFont systemFontOfSize:fmax(8,d*.088) weight:self.bottom?UIFontWeightMedium:UIFontWeightSemibold], NSForegroundColorAttributeName:self.ink ?: UIColor.whiteColor};
    NSMutableArray<NSString *> *glyphs = [NSMutableArray array];
    CGFloat ellipsis = [@"…" sizeWithAttributes:attrs].width;
    __block CGFloat width = 0;
    [self.text enumerateSubstringsInRange:NSMakeRange(0,self.text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *part, NSRange partRange, NSRange enclosing, BOOL *stop) {
        CGFloat step = [part sizeWithAttributes:attrs].width;
        if (width+step+(NSMaxRange(partRange)<self.text.length ? ellipsis:0)>limit) {
            [glyphs addObject:@"…"]; width += ellipsis; *stop = YES;
        } else { [glyphs addObject:part]; width += step; }
    }];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    if (self.axs_twindial_separateBands) {
        // Keep both lyrics and metadata away from the center controls and each other.
        CGRect band = self.bottom ? CGRectMake(CGRectGetMinX(self.bounds), center.y+d*.23, d, d*.27)
                                  : CGRectMake(CGRectGetMinX(self.bounds), CGRectGetMinY(self.bounds), d, d*.36);
        CGContextClipToRect(ctx, band);
    }
    CGFloat x = -width/2;
    for (NSString *glyph in glyphs) {
        CGSize size = [glyph sizeWithAttributes:attrs];
        CGFloat angle = (x+size.width/2)/r;
        CGFloat side = self.bottom ? 1 : -1;
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx,center.x+r*sin(angle),center.y+side*r*cos(angle));
        CGContextRotateCTM(ctx,-side*angle);
        [glyph drawAtPoint:CGPointMake(-size.width/2,-size.height/2) withAttributes:attrs];
        CGContextRestoreGState(ctx);
        x += size.width;
    }
    CGContextRestoreGState(ctx);
}
@end
