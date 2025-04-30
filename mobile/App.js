//  Mobile entry; initialize firebase in app.js; Ensure Inter font is loaded in App.js

import analytics from '@react-native-firebase/analytics';
import { useFonts, Inter_400Regular, Inter_700Bold } from '@react-native-google-fonts/inter';

async function initializeAnalytics() {
  await analytics().setAnalyticsCollectionEnabled(true);
}
initializeAnalytics();

const App = () => {
  const [fontsLoaded] = useFonts({ Inter_400Regular, Inter_700Bold });
  if (!fontsLoaded) return null;
  return <AnalyticsDashboard />;
};
export default App;
