import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:jarvis/core/network/connectivity_cubit.dart';
import 'package:jarvis/core/utils/constants.dart';
import 'package:jarvis/di/injection.dart';
import 'package:jarvis/features/chat/presentation/bloc/chat_bloc.dart';
import 'package:jarvis/features/chat/presentation/bloc/chat_event.dart';
import 'package:jarvis/features/chat/presentation/pages/chat_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await configureDependencies();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.chatBloc, this.connectivityCubit});

  final ChatBloc? chatBloc;
  final ConnectivityCubit? connectivityCubit;

  @override
  Widget build(BuildContext context) {
    final child = MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConstants.appTitle,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const ChatPage(),
    );

    if (chatBloc != null) {
      return MultiBlocProvider(
        providers: [
          BlocProvider.value(value: chatBloc!),
          if (connectivityCubit != null)
            BlocProvider.value(value: connectivityCubit!)
          else
            BlocProvider(create: (_) => getIt<ConnectivityCubit>()),
        ],
        child: child,
      );
    }

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => getIt<ChatBloc>()..add(const LoadChatHistoryEvent()),
        ),
        BlocProvider(create: (_) => getIt<ConnectivityCubit>()),
      ],
      child: child,
    );
  }
}
