#ifndef GrokIcon_h
#define GrokIcon_h

#import <Cocoa/Cocoa.h>

static NSArray<NSNumber *> *GrokParseSVGNumbers(NSString *string, NSUInteger *index) {
    NSMutableArray<NSNumber *> *numbers = [NSMutableArray array];
    NSUInteger length = string.length;
    NSUInteger i = *index;
    while (i < length) {
        unichar ch = [string characterAtIndex:i];
        if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == ',') {
            i++;
            continue;
        }
        if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z')) {
            break;
        }
        NSUInteger start = i;
        if (ch == '+' || ch == '-') {
            i++;
        }
        BOOL seenDigit = NO;
        while (i < length) {
            ch = [string characterAtIndex:i];
            if (ch >= '0' && ch <= '9') {
                seenDigit = YES;
                i++;
                continue;
            }
            if (ch == '.' ) {
                i++;
                continue;
            }
            if ((ch == 'e' || ch == 'E') && i + 1 < length) {
                i++;
                ch = [string characterAtIndex:i];
                if (ch == '+' || ch == '-') {
                    i++;
                }
                continue;
            }
            break;
        }
        if (!seenDigit || i == start) {
            break;
        }
        [numbers addObject:@([[string substringWithRange:NSMakeRange(start, i - start)] doubleValue])];
    }
    *index = i;
    return numbers;
}

static NSBezierPath *GrokBezierPathFromSVG(NSString *svgPath) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    NSUInteger i = 0;
    NSUInteger length = svgPath.length;
    unichar command = 0;
    NSPoint current = NSZeroPoint;
    NSPoint startPoint = NSZeroPoint;

    while (i < length) {
        unichar ch = [svgPath characterAtIndex:i];
        if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == ',') {
            i++;
            continue;
        }
        if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z')) {
            command = ch;
            i++;
        }
        if (command == 0) {
            break;
        }

        BOOL relative = command >= 'a';
        unichar kind = (unichar)tolower(command);
        if (kind == 'z') {
            [path closePath];
            current = startPoint;
            continue;
        }

        NSArray<NSNumber *> *numbers = GrokParseSVGNumbers(svgPath, &i);
        if (numbers.count == 0) {
            break;
        }

        NSUInteger n = 0;
        while (n < numbers.count) {
            if (kind == 'm') {
                if (n + 1 >= numbers.count) {
                    break;
                }
                double x = numbers[n].doubleValue;
                double y = numbers[n + 1].doubleValue;
                n += 2;
                if (relative) {
                    x += current.x;
                    y += current.y;
                }
                current = NSMakePoint(x, y);
                startPoint = current;
                [path moveToPoint:current];
                kind = 'l';
                command = relative ? 'l' : 'L';
            } else if (kind == 'l') {
                if (n + 1 >= numbers.count) {
                    break;
                }
                double x = numbers[n].doubleValue;
                double y = numbers[n + 1].doubleValue;
                n += 2;
                if (relative) {
                    x += current.x;
                    y += current.y;
                }
                current = NSMakePoint(x, y);
                [path lineToPoint:current];
            } else if (kind == 'h') {
                double x = numbers[n].doubleValue;
                n += 1;
                if (relative) {
                    x += current.x;
                }
                current = NSMakePoint(x, current.y);
                [path lineToPoint:current];
            } else if (kind == 'v') {
                double y = numbers[n].doubleValue;
                n += 1;
                if (relative) {
                    y += current.y;
                }
                current = NSMakePoint(current.x, y);
                [path lineToPoint:current];
            } else if (kind == 'c') {
                if (n + 5 >= numbers.count) {
                    break;
                }
                double x1 = numbers[n].doubleValue;
                double y1 = numbers[n + 1].doubleValue;
                double x2 = numbers[n + 2].doubleValue;
                double y2 = numbers[n + 3].doubleValue;
                double x = numbers[n + 4].doubleValue;
                double y = numbers[n + 5].doubleValue;
                n += 6;
                if (relative) {
                    x1 += current.x; y1 += current.y;
                    x2 += current.x; y2 += current.y;
                    x += current.x; y += current.y;
                }
                [path curveToPoint:NSMakePoint(x, y)
                     controlPoint1:NSMakePoint(x1, y1)
                     controlPoint2:NSMakePoint(x2, y2)];
                current = NSMakePoint(x, y);
            } else {
                n = numbers.count;
            }
        }
    }
    return path;
}

// Official Grok G-mark: accretion-disk black hole with a slash through it.
static NSImage *GrokBlackHoleIconWithSize(CGFloat size) {
    static NSString * const PathA =
        @"M395.479 633.828L735.91 381.105C752.599 368.715 776.454 373.548 784.406 392.792C826.26 494.285 807.561 616.253 724.288 699.996C641.016 783.739 525.151 802.104 419.247 760.277L303.556 814.143C469.49 928.202 670.987 899.995 796.901 773.282C896.776 672.843 927.708 535.937 898.785 412.476L899.047 412.739C857.105 231.37 909.358 158.874 1016.4 10.6326C1018.93 7.11771 1021.47 3.60279 1024 0L883.144 141.651V141.212L395.392 633.916";
    static NSString * const PathB =
        @"M325.226 695.251C206.128 580.84 226.662 403.776 328.285 301.668C403.431 226.097 526.549 195.254 634.026 240.596L749.454 186.994C728.657 171.88 702.007 155.623 671.424 144.2C533.19 86.9942 367.693 115.465 255.323 228.382C147.234 337.081 113.244 504.215 171.613 646.833C215.216 753.423 143.739 828.818 71.7385 904.916C46.2237 931.893 20.6216 958.87 0 987.429L325.139 695.339";

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocusFlipped:YES];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    [NSColor.blackColor setFill];

    CGFloat scale = size / 1024.0;
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform scaleBy:scale];
    [transform concat];

    [GrokBezierPathFromSVG(PathA) fill];
    [GrokBezierPathFromSVG(PathB) fill];
    [image unlockFocus];
    image.template = YES;
    image.accessibilityDescription = @"Grok";
    return image;
}

static NSImage *GrokBlackHoleIcon(void) {
    return GrokBlackHoleIconWithSize(18.0);
}

static BOOL GrokWritePNG(NSImage *image, NSString *path, NSError **error) {
    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (cgImage == NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"GrokIcon" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Could not render icon"}];
        }
        return NO;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    rep.size = image.size;
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [png writeToFile:path options:NSDataWritingAtomic error:error];
}

#endif
