import 'package:collection/collection.dart';
import 'package:example/gen/flutter_widget_skewer.g.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Widget Skewer Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Widget Skewer Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  /// A Widget may like this, Column + Padding + Center + ColorBox ...
  Widget get flutterWidget => ColoredBox(
        color: Colors.green,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 8,
              children: _columnChildren,
            ),
          ),
        ),
      );

  /// ↓↓↓↓↓↓↓↓↓↓↓↓↓↓ VS ↓↓↓↓↓↓↓↓↓↓↓↓↓↓

  /// Using [flutter_widget_skewer] to write same widget.
  Widget get withWidgetSkewer => _columnChildren
      .column(mainAxisAlignment: MainAxisAlignment.center, spacing: 8)
      .padding(padding: EdgeInsets.all(16))
      .center()
      .coloredBox(color: Colors.green);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      backgroundColor: Colors.black54,
      body: Column(
        children: [
          // sample widget flutterWidget & withWidgetSkewer
          /*_card(
            Column(
              children: [
                _title('Sample Widget: flutterWidget'),
                flutterWidget,
                withWidgetSkewer,
              ],
            ),
          ),*/
          _card(
            Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        _title('flutterWidget'),
                        Text('''
ColoredBox(
  color: Colors.green,
  child: Center(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 8,
        children: _columnChildren,
      ),
    ),
  ),
);'''
                            .split('\n')
                            .mapIndexed(
                              (index, element) => '$index\t\t$element',
                            )
                            .join('\n'))
                      ],
                    ).expanded(),
                    _title('VS'),
                    Column(
                      children: [
                        _title('withWidgetSkewer'),
                        Text('''
_columnChildren
.column(mainAxisAlignment: MainAxisAlignment.center, spacing: 8)
.padding(padding: EdgeInsets.all(16))
.center()
.coloredBox(color: Colors.green);'''
                            .split('\n')
                            .mapIndexed(
                              (index, element) => '$index\t\t$element',
                            )
                            .join('\n'))
                      ],
                    ).expanded(),
                  ],
                ),
              ],
            ),
          ),
          _card(
            Column(
              children: [
                _title('List<Widget> extension'),
                Row(
                  children: [
                    _columnChildren.column().expanded(),
                    VerticalDivider(
                      color: Colors.grey,
                      indent: 50,
                    ),
                    Text('''List<Widget> get _columnChildren => <Widget>[
        const Text(
          'You have pushed the button this many times:',
        ),
        Text(
          '$_counter',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ];
      
_columnChildren.column();''').expanded()
                  ],
                )
              ],
            ),
          )
        ],
      ).singleChildScrollView(),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  List<Widget> get _columnChildren => <Widget>[
        const Text(
          'You have pushed the button this many times:',
        ),
        Text(
          '$_counter',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ];

  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  Widget _title(String title) => Text(
        title,
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ).container(
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.grey));

  Widget _card(Widget content) => content.card(
        margin: EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
      );
}
