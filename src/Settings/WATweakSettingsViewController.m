#import "WATweakSettingsViewController.h"
#import "WATweakSettings.h"
#import "../Translation/WATranslationManager.h"
#import "../IconPicker/WAIconPickerViewController.h"
#import "../Common.h"

@interface WATweakSettingsViewController ()
@end

@implementation WATweakSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WhatsAppPlus 设置";
    UIBarButtonItem *closeBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissSelf)];
    self.navigationItem.rightBarButtonItem = closeBtn;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 6; // 发送翻译
        case 1: return 6; // 翻译用量
        case 2: return 2; // 图标与外观
        case 3: return 2; // 关于
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"🌐 发送翻译";
        case 1: return @"📊 翻译用量";
        case 2: return @"🎨 图标与外观";
        case 3: return @"ℹ️ 关于插件";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"输入中文停顿 1.5 秒自动翻译为双语显示在输入框，点发送即发出。三引擎链路：Google Cloud 官方 API（需自配 Key）→ Google 免费接口 → MyMemory 兜底。";
        case 1: return @"本地统计，仅记录本插件的翻译调用量。";
        case 2: return @"自由更换应用桌面图标，并可解锁 Meta 实验室毛玻璃 UI。";
        case 3: return nil;
        default: return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"WAPlusSettingCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellID];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = nil;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.numberOfLines = 1;
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    WATweakSettings *settings = [WATweakSettings sharedSettings];

    if (indexPath.section == 0) {
        // 发送翻译
        if (indexPath.row == 0) {
            cell.textLabel.text = @"发送时自动翻译";
            cell.detailTextLabel.text = @"输入中文自动转英语";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = settings.autoTranslateOutgoing;
            [sw addTarget:self action:@selector(outgoingTranslateToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"双语发送";
            cell.detailTextLabel.text = @"开=中英双语，关=只发英语";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = settings.bilingualOutgoing;
            [sw addTarget:self action:@selector(bilingualOutgoingToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"发送目标语言";
            NSString *langName = [WATweakSettings supportedLanguages][settings.outgoingTargetLanguage] ?: settings.outgoingTargetLanguage;
            cell.detailTextLabel.text = langName;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"翻译引擎";
            cell.detailTextLabel.text = (settings.translationEngine == WATranslationEngineGoogleCloud) ? @"Google Cloud" : @"Google 免费 (+MyMemory)";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"Google Cloud API Key";
            if (settings.googleCloudApiKey.length > 8) {
                NSString *masked = [NSString stringWithFormat:@"%@****%@", [settings.googleCloudApiKey substringToIndex:4], [settings.googleCloudApiKey substringFromIndex:settings.googleCloudApiKey.length - 4]];
                cell.detailTextLabel.text = masked;
            } else if (settings.googleCloudApiKey.length > 0) {
                cell.detailTextLabel.text = @"已配置";
            } else {
                cell.detailTextLabel.text = @"未配置 (点击设置)";
            }
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else if (indexPath.row == 5) {
            cell.textLabel.text = @"清除翻译缓存";
            cell.textLabel.textColor = [UIColor systemRedColor];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    } else if (indexPath.section == 1) {
        // 翻译用量
        NSDictionary *stats = [[WATranslationManager sharedManager] usageStatistics];
        if (indexPath.row == 0) {
            cell.textLabel.text = @"今日用量";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ 字符 / %@ 次", stats[@"todayChars"], stats[@"todayCalls"]];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"累计用量";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ 字符 / %@ 次", stats[@"totalChars"], stats[@"totalCalls"]];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Google 免费接口";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ 字符", stats[@"googleFreeChars"]];
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Google Cloud";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ 字符", stats[@"googleCloudChars"]];
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"MyMemory";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ 字符", stats[@"myMemoryChars"]];
        } else if (indexPath.row == 5) {
            cell.textLabel.text = @"重置统计";
            cell.textLabel.textColor = [UIColor systemRedColor];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    } else if (indexPath.section == 2) {
        // 图标与外观
        if (indexPath.row == 0) {
            cell.textLabel.text = @"更换应用桌面图标";
            cell.detailTextLabel.text = @"点击进入选择";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Liquid Glass 毛玻璃界面";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = settings.liquidGlassEnabled;
            [sw addTarget:self action:@selector(liquidGlassToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
    } else if (indexPath.section == 3) {
        // 关于
        if (indexPath.row == 0) {
            cell.textLabel.text = @"当前版本";
            cell.detailTextLabel.text = TWEAK_VERSION;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"插件作者";
            cell.detailTextLabel.text = @"telegram@bengege";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    }
    return cell;
}

#pragma mark - Table View Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        if (indexPath.row == 2) {
            [self selectLanguageForOutgoing];
        } else if (indexPath.row == 3) {
            [self selectTranslationEngine];
        } else if (indexPath.row == 4) {
            [self promptForGoogleCloudApiKey];
        } else if (indexPath.row == 5) {
            [[WATranslationManager sharedManager] clearCache];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"翻译缓存已清空" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 5) {
            [[WATranslationManager sharedManager] resetUsageStatistics];
            [self.tableView reloadData];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" message:@"用量统计已重置" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            WAIconPickerViewController *iconVC = [[WAIconPickerViewController alloc] init];
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:iconVC];
            nav.modalPresentationStyle = UIModalPresentationFormSheet;
            [self presentViewController:nav animated:YES completion:nil];
        }
    } else if (indexPath.section == 3) {
        if (indexPath.row == 1) {
            NSURL *url = [NSURL URLWithString:@"https://t.me/bengege"];
            if ([[UIApplication sharedApplication] canOpenURL:url]) {
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            }
        }
    }
}

#pragma mark - Toggle Actions

- (void)outgoingTranslateToggled:(UISwitch *)sw {
    [WATweakSettings sharedSettings].autoTranslateOutgoing = sw.isOn;
    [[WATweakSettings sharedSettings] save];
}

- (void)bilingualOutgoingToggled:(UISwitch *)sw {
    [WATweakSettings sharedSettings].bilingualOutgoing = sw.isOn;
    [[WATweakSettings sharedSettings] save];
}

- (void)liquidGlassToggled:(UISwitch *)sw {
    [WATweakSettings sharedSettings].liquidGlassEnabled = sw.isOn;
    [[WATweakSettings sharedSettings] save];
}

#pragma mark - Language & Engine Selection

- (void)selectLanguageForOutgoing {
    WATweakSettings *settings = [WATweakSettings sharedSettings];
    NSDictionary *langs = [WATweakSettings supportedLanguages];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"发送目标语言" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *code in langs) {
        NSString *name = langs[code];
        UIAlertAction *action = [UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            settings.outgoingTargetLanguage = code;
            [settings save];
            [self.tableView reloadData];
        }];
        [alert addAction:action];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)selectTranslationEngine {
    WATweakSettings *settings = [WATweakSettings sharedSettings];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"翻译引擎" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Google 免费接口 (+MyMemory 兜底)" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        settings.translationEngine = WATranslationEngineGoogleFree;
        [settings save];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Google Cloud 官方 API" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        settings.translationEngine = WATranslationEngineGoogleCloud;
        [settings save];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptForGoogleCloudApiKey {
    WATweakSettings *settings = [WATweakSettings sharedSettings];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Google Cloud API Key" message:@"输入你的 Google Cloud Translation API Key" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"API Key";
        textField.text = settings.googleCloudApiKey;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        settings.googleCloudApiKey = alert.textFields.firstObject.text ?: @"";
        [settings save];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
