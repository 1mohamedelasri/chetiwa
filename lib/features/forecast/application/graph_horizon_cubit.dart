import 'package:flutter_bloc/flutter_bloc.dart';

enum GraphHorizon { twoHours, twentyFourHours }

final class GraphHorizonCubit extends Cubit<GraphHorizon> {
  GraphHorizonCubit() : super(GraphHorizon.twoHours);

  void select(GraphHorizon horizon) => emit(horizon);
}
