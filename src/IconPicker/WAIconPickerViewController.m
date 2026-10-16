#import "WAIconPickerViewController.h"
#import "../Settings/WATweakSettings.h"
#import "../Common.h"

static NSArray<NSString *> *WAIconNames(void) {
    static NSArray<NSString *> *icons;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        icons = @[
            @"Default",
            @"AppIcon-01", @"AppIcon-02", @"AppIcon-03", @"AppIcon-04", @"AppIcon-05",
            @"AppIcon-06", @"AppIcon-07", @"AppIcon-08", @"AppIcon-09", @"AppIcon-10",
            @"AppIcon-11", @"AppIcon-12", @"AppIcon-13", @"AppIcon-14"
        ];
    });
    return icons;
}

static UIImage *WAIconPreviewForName(NSString *iconName) {
    if ([iconName isEqualToString:@"Default"]) {
        return [UIImage imageNamed:@"AppIcon60x60"] ?: [UIImage imageNamed:@"AppIcon"];
    }

    return [UIImage imageNamed:[NSString stringWithFormat:@"%@@3x", iconName]]
        ?: [UIImage imageNamed:[NSString stringWithFormat:@"%@@2x", iconName]]
        ?: [UIImage imageNamed:iconName];
}

static UIImage *WARoundedIconPreview(UIImage *image) {
    if (!image) return nil;

    CGSize size = CGSizeMake(46.0, 46.0);
    CGRect rect = CGRectMake(0.0, 0.0, size.width, size.height);

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = [UIScreen mainScreen].scale;

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];

    return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:12.0] addClip];
        [image drawInRect:rect];
    }];
}

@implementation WAIconPickerViewController

+ (void)applyLiquidGlassDefaultsIfNeeded {
    if (![WATweakSettings sharedSettings].liquidGlassEnabled) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:@"liquid_glass_override_enabled"];
    [defaults setBool:YES forKey:@"WALiquidGlassOverrideEnabled"];
    [defaults setBool:YES forKey:@"ios_liquid_glass_enabled"];
    [defaults setBool:YES forKey:@"ios_liquid_glass_launched"];
    [defaults setBool:YES forKey:@"ios_liquid_glass_m1"];
    [defaults setBool:YES forKey:@"ios_liquid_glass_m_1_5"];
    [defaults setBool:YES forKey:@"ios_liquid_glass_m_1_5_context_menu"];
    [defaults setBool:YES forKey:@"ios_liquid_glass_media_m0"];
    [defaults setBool:YES forKey:@"ios_liquid_glass_larger_composer"];
    [defaults setBool:YES forKey:@"ios_liquid_glass_media_editor_enabled"];
    [defaults setBool:YES forKey:@"ios_liquid_glass_calling_improvement_enabled"];
    [defaults setBool:YES forKey:@"ios_liquid_glass_workaround_attachment_tray"];
    [defaults setBool:YES forKey:@"status_viewer_redesign_enabled"];
    [defaults synchronize];
}

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = @"更换应用图标";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 68.0;
    
    UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissPicker)];
    self.navigationItem.rightBarButtonItem = closeItem;
}

- (void)dismissPicker {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (section == 0) ? WAIconNames().count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return (section == 0) ? @"可选图标 (App Icons)" : @"Meta 实验室特性 (Liquid Glass)";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"点击图标即可实时切换 WhatsApp 桌面显示图标，无需注销 (Respring)。";
    }
    return @"开启 Liquid Glass 磨砂毛玻璃新版 UI 后，需重启 WhatsApp 生效。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        static NSString *glassCellID = @"WALiquidGlassCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:glassCellID];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:glassCellID];
        }
        
        BOOL enabled = [WATweakSettings sharedSettings].liquidGlassEnabled;
        cell.textLabel.text = @"开启 Liquid Glass 毛玻璃界面";
        cell.detailTextLabel.text = enabled ? @"已启用 (需完全重启 WhatsApp 体验)" : @"已关闭";
        cell.imageView.image = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = enabled;
        [toggle addTarget:self action:@selector(liquidGlassToggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        return cell;
    }
    
    static NSString *iconCellID = @"WAIconCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:iconCellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:iconCellID];
    }
    
    NSString *iconName = WAIconNames()[indexPath.row];
    NSString *currentIcon = [[UIApplication sharedApplication] alternateIconName];
    
    BOOL isCurrent = NO;
    if ([iconName isEqualToString:@"Default"]) {
        isCurrent = (currentIcon == nil);
    } else {
        isCurrent = [currentIcon isEqualToString:iconName];
    }
    
    cell.textLabel.text = iconName;
    cell.detailTextLabel.text = isCurrent ? @"✓ 当前正在使用" : (indexPath.row == 0 ? @"官方原生图标" : @"点击即可应用");
    cell.imageView.image = WARoundedIconPreview(WAIconPreviewForName(iconName));
    cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
    cell.imageView.clipsToBounds = YES;
    cell.accessoryType = isCurrent ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == 1) return;
    
    if (![UIApplication sharedApplication].supportsAlternateIcons) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"不支持" message:@"当前设备或系统环境不支持更换应用图标。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    NSString *iconName = WAIconNames()[indexPath.row];
    NSString *targetIcon = [iconName isEqualToString:@"Default"] ? nil : iconName;
    
    [[UIApplication sharedApplication] setAlternateIconName:targetIcon completionHandler:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"更换失败" message:error.localizedDescription ?: @"无法更换图标" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            } else {
                [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
            }
        });
    }];
}

- (void)liquidGlassToggleChanged:(UISwitch *)sender {
    [WATweakSettings sharedSettings].liquidGlassEnabled = sender.isOn;
    [[WATweakSettings sharedSettings] save];
    [WAIconPickerViewController applyLiquidGlassDefaultsIfNeeded];
    
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"需重启生效" message:@"Liquid Glass 毛玻璃全新界面设置已更新，请退出并在后台完全关闭 WhatsApp 后重新打开生效。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"我知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
