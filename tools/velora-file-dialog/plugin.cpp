// SPDX-License-Identifier: GPL-3.0-only
// Restore KIO's existing New Folder action without changing dialog semantics.
#include <QApplication>
#include <QGenericPlugin>
#include <QPointer>
#include <QTimer>
#include <QToolBar>
#include <QToolButton>
#include <QBoxLayout>
#include <KDirOperator>
#include <KFileWidget>

class FolderButton : public QObject {
    Q_OBJECT
public:
    explicit FolderButton(QObject *parent) : QObject(parent) {
        // Generic plugins are constructed before QApplication finishes initializing.
        QTimer::singleShot(0, this, [this] {
            if (qobject_cast<QApplication *>(QCoreApplication::instance())) {
                qApp->installEventFilter(this);
                // Some clients show their dialog before entering the event loop.
                for (auto *widget : QApplication::allWidgets())
                    if (auto *fileWidget = qobject_cast<KFileWidget *>(widget); fileWidget && fileWidget->isVisible())
                        attach(fileWidget);
            }
        });
    }
    bool eventFilter(QObject *object, QEvent *event) override {
        if (event->type() == QEvent::Show) {
            if (auto *widget = qobject_cast<KFileWidget *>(object)) {
                QPointer<KFileWidget> guarded(widget);
                QTimer::singleShot(0, widget, [guarded] { if (guarded) attach(guarded); });
            }
        }
        return false;
    }
private:
    static void attach(KFileWidget *widget) {
        auto *op = widget->dirOperator();
        auto *action = op->action(KDirOperator::NewFolder);
        // KIO names its toolbar; preview widgets can contain unrelated toolbars.
        const auto bars = widget->findChildren<QToolBar *>(QStringLiteral("KFileWidget::toolbar"), Qt::FindChildrenRecursively);
        if (!action || bars.size() != 1)
            return;
        auto *bar = bars.first();
        auto *button = widget->findChild<QToolButton *>(QStringLiteral("velora-create-folder"));
        if (!button) {
            // Pin the existing action outside QToolBar's overflow area. Narrow file
            // dialogs otherwise hide the last action behind the overflow chevron.
            auto *parent = bar->parentWidget();
            auto *layout = qobject_cast<QBoxLayout *>(parent->layout());
            if (!layout || layout->indexOf(bar) < 0) return;
            const int position = layout->indexOf(bar);
            layout->removeWidget(bar);
            auto *strip = new QWidget(parent);
            auto *row = new QHBoxLayout(strip);
            row->setContentsMargins(0, 0, 0, 0);
            row->setSpacing(4);
            row->addWidget(bar, 1);
            button = new QToolButton(strip);
            button->setObjectName(QStringLiteral("velora-create-folder"));
            button->setAutoRaise(true);
            button->setIconSize(bar->iconSize());
            button->setDefaultAction(action);
            row->addWidget(button);
            layout->insertWidget(position, strip);
        }
        bar->removeAction(action);
        action->setVisible(true);
        // mkdir() retains KIO's permission checks and translated error dialogs.
        action->setEnabled(true);
    }
};

class VeloraFileDialogPlugin : public QGenericPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QGenericPluginFactoryInterface" FILE "plugin.json")
public:
    QObject *create(const QString &key, const QString &) override {
        return key == QStringLiteral("velora-file-dialog") ? new FolderButton(nullptr) : nullptr;
    }
};

#include "plugin.moc"
