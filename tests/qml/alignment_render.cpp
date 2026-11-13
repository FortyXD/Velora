// QQuickWindow::grabWindow preserves the actual device pixel ratio. Qt Quick
// Test's grabImage(Item) can clip native text at DPR != 1 on the software backend.
#include <QGuiApplication>
#include <QImage>
#include <QQuickView>
#include <QTimer>

int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    if (argc != 3) return 1;
    QQuickView view;
    view.setSource(QUrl::fromLocalFile(argv[1]));
    if (view.status() != QQuickView::Ready) return 2;
    view.show();
    QTimer::singleShot(200, [&]() {
        app.exit(view.grabWindow().save(argv[2]) ? 0 : 3);
    });
    return app.exec();
}
