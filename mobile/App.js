//  Mobile entry; initialize firebase in app.js
import analytics from '@react-native-firebase/analytics';

async function initializeAnalytics() {
  await analytics().setAnalyticsCollectionEnabled(true);
}
initializeAnalytics();
