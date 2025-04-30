// Initialize firebase in App.js
import analytics from '@react-native-firebase/analytics';
import { useFonts, Inter_400Regular, Inter_700Bold } from '@react-native-google-fonts/inter';

const App = () => {
  const [fontsLoaded] = useFonts({ Inter_400Regular, Inter_700Bold });
  if (!fontsLoaded) return null;
  return <AnalyticsDashboard />;
};

async function initializeAnalytics() {
  await analytics().setAnalyticsCollectionEnabled(true);
}
initializeAnalytics();
