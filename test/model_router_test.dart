import 'package:flutter_test/flutter_test.dart';
import 'package:cystem/services/model_router.dart';
import 'package:cystem/core/constants/model_constants.dart';

void main(){final router=ModelRouter();test('detects web intent',(){final route=router.route(prompt:'what is the latest weather?',forceWeb:false,forceImage:false,selectedModel:ModelIds.nemotronSuper);expect(route.useWeb,true);});test('force image wins',(){final route=router.route(prompt:'tell me about cars',forceWeb:false,forceImage:true,selectedModel:ModelIds.nemotronSuper);expect(route.model,ModelIds.geminiImage);expect(route.useImages,true);});}
