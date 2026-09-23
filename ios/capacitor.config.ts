import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.auktsionmonet.app',
  appName: 'Аукцион Монет',
  webDir: 'www',
  ios: {
    contentInset: 'automatic',
    allowsLinkPreview: false,
    scrollEnabled: false,              // игра не должна прокручиваться
    preferredContentMode: 'mobile',
  },
  plugins: {
    SplashScreen: {
      launchShowDuration:    2000,
      launchAutoHide:        true,
      backgroundColor:       '#0d1420',
      iosSpinnerStyle:       'small',
      spinnerColor:          '#e8b54d',
      showSpinner:           true,
    },
    StatusBar: {
      style:           'dark',
      backgroundColor: '#0d1420',
      overlaysWebView: false,
    },
    Keyboard: {
      resize:           'body',
      resizeOnFullScreen: true,
    },
  },
  server: {
    // В продакшене укажи свой домен если будет веб-версия
    // url: 'https://auktsionmonet.com',
    cleartext: false,                  // только HTTPS
    androidScheme: 'https',
  },
};

export default config;
