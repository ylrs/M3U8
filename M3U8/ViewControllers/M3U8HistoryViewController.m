//
//  M3U8HistoryViewController.m
//  M3U8Converter
//

#import "M3U8HistoryViewController.h"

@interface M3U8HistoryViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *historyItems;

@end

@implementation M3U8HistoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"历史记录";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.historyItems = [NSMutableArray array];

    [self setupUI];
    [self loadHistory];
}

#pragma mark - UI Setup

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 80;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"HistoryCell"];
    [self.view addSubview:self.tableView];

    // 添加清空按钮
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                                                           target:self
                                                                                           action:@selector(clearHistory)];
}

#pragma mark - Data Loading

- (void)loadHistory {
    // TODO: 从 Core Data 或本地存储加载历史记录
    // 这里先使用空数组
    [self.tableView reloadData];
}

#pragma mark - Actions

- (void)clearHistory {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认清空"
                                                                   message:@"是否清空所有历史记录？"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self.historyItems removeAllObjects];
        [self.tableView reloadData];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.historyItems.count == 0) {
        UILabel *emptyLabel = [[UILabel alloc] initWithFrame:self.tableView.bounds];
        emptyLabel.text = @"暂无历史记录";
        emptyLabel.textColor = [UIColor secondaryLabelColor];
        emptyLabel.textAlignment = NSTextAlignmentCenter;
        self.tableView.backgroundView = emptyLabel;
    } else {
        self.tableView.backgroundView = nil;
    }

    return self.historyItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"HistoryCell" forIndexPath:indexPath];

    // TODO: 配置 cell
    cell.textLabel.text = @"历史记录项";

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
