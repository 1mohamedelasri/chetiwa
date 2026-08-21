import 'package:flutter_bloc/flutter_bloc.dart';

enum WeatherSection { graph, radar, forecast }

final class WeatherSectionCubit extends Cubit<WeatherSection> {
  WeatherSectionCubit() : super(WeatherSection.graph);

  void select(WeatherSection section) => emit(section);
}
