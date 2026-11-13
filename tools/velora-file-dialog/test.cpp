// SPDX-License-Identifier: GPL-3.0-only
#include <QApplication>
#include <QTemporaryDir>
#include <QTest>
#include <QToolBar>
#include <QToolButton>
#include <QDialog>
#include <QDialogButtonBox>
#include <QPushButton>
#include <QLineEdit>
#include <QTimer>
#include <QFileInfo>
#include <KDirOperator>
#include <KFileWidget>

class DialogTest : public QObject {
    Q_OBJECT
private Q_SLOTS:
    void modes_data() {
        QTest::addColumn<int>("operation");
        QTest::newRow("open") << int(KFileWidget::Opening);
        QTest::newRow("save") << int(KFileWidget::Saving);
        QTest::newRow("directory") << int(KFileWidget::Other);
    }
    void modes() {
        QFETCH(int, operation);
        QTemporaryDir dir;
        KFileWidget widget(QUrl::fromLocalFile(dir.path() + "/"));
        widget.setOperationMode(KFileWidget::OperationMode(operation));
        widget.setMode(operation == KFileWidget::Other ? KFile::Directory : KFile::File);
        widget.resize(800, 600);
        widget.show();
        auto *action = widget.dirOperator()->action(KDirOperator::NewFolder);
        auto bars = widget.findChildren<QToolBar *>(QStringLiteral("KFileWidget::toolbar"), Qt::FindChildrenRecursively);
        QCOMPARE(bars.size(), 1);
        QTRY_VERIFY(action->isEnabled());
        QTRY_VERIFY(widget.findChild<QToolButton *>(QStringLiteral("velora-create-folder")));
        QCOMPARE(widget.findChildren<QToolButton *>(QStringLiteral("velora-create-folder")).size(), 1);
        QCOMPARE(widget.findChild<QToolButton *>(QStringLiteral("velora-create-folder"))->defaultAction(), action);
        QCOMPARE(int(widget.operationMode()), operation);
        const QString folderName = QString::fromUtf8("Папка с пробелами");
        bool edited = false;
        QTimer::singleShot(100, &widget, [&edited, &folderName] {
            for (auto *top : QApplication::topLevelWidgets()) {
                auto *dialog = qobject_cast<QDialog *>(top);
                if (!dialog || !dialog->isVisible()) continue;
                auto *edit = dialog->findChild<QLineEdit *>();
                if (!edit) continue;
                edit->setText(folderName);
                edited = true;
                auto *buttons = dialog->findChild<QDialogButtonBox *>();
                if (buttons && buttons->button(QDialogButtonBox::Ok))
                    buttons->button(QDialogButtonBox::Ok)->click();
                break;
            }
        });
        action->trigger();
        QTRY_VERIFY(edited);
        QTRY_VERIFY(QFileInfo::exists(dir.path() + "/" + folderName));
        QCOMPARE(int(widget.operationMode()), operation);
        widget.hide();
        widget.show();
        QTRY_VERIFY(widget.findChild<QToolButton *>(QStringLiteral("velora-create-folder")));
        QCOMPARE(widget.findChildren<QToolButton *>(QStringLiteral("velora-create-folder")).size(), 1);
        QCOMPARE(widget.findChild<QToolButton *>(QStringLiteral("velora-create-folder"))->defaultAction(), action);
    }
};
QTEST_MAIN(DialogTest)
#include "test.moc"
