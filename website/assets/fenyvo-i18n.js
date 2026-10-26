(function () {
  'use strict';

  const storageKey = 'fenyvo.website.language';
  const supported = ['ru', 'uk', 'en'];

  const messages = {
    ru: {
      galleryKicker: 'FENYVO 1.8.2+4251',
      galleryTitle: 'FENYVO в действии',
      galleryIntro: 'Настоящие скриншоты приложения на Android и Windows. Нажмите на изображение, чтобы открыть его крупнее.',
      galleryNote: 'Реальные экраны приложения с демонстрационными именами.',
      galleryAndroidLogin: 'Вход',
      galleryAndroidPassword: 'Пароль',
      galleryAndroidConfirm: 'Подтверждение пароля',
      galleryAndroidMatch: 'Пароли совпадают',
      galleryAndroidScroll: 'Регистрация с прокруткой',
      galleryWindowsLogin: 'Вход на Windows',
      galleryWindowsRegistration: 'Регистрация на Windows',

      auto: 'Как на устройстве',
      languageCaption: 'Язык:',
      languageLabel: 'Язык сайта',
      homeLabel: 'Fenyvo — на главную',
      navLabel: 'Основная навигация',
      interfaceLabel: 'Пример интерфейса Fenyvo',
      pageTitle: 'Fenyvo — приватное общение без лишнего',
      pageDescription: 'Fenyvo — мессенджер для Android и Windows: личные и групповые чаты, звонки, контакты, файлы и медиа. Общение без лишнего шума.',
      ogTitle: 'Fenyvo — мессенджер',
      ogDescription: 'Fenyvo — общение без лишнего шума. Чаты, звонки, контакты и фирменный интерфейс для Android и Windows.',
      features: 'Возможности',
      interface: 'Интерфейс',
      security: 'Безопасность',
      download: 'Скачать',
      sharedContact: 'Вам поделились контактом',
      contactHelp: 'Если Fenyvo уже установлен, откройте карточку пользователя. Если приложения нет — установите его, вернитесь на эту страницу и нажмите «Открыть контакт» ещё раз.',
      openContact: 'Открыть контакт в Fenyvo',
      downloadAndroid: 'Скачать для Android',
      publicVersion: 'Тестовая версия 1.8.2 · Android 4251 · Windows 4251',
      heroLeadA: 'Общение без',
      heroLeadB: 'лишнего шума',
      heroDescription: 'Личные и групповые чаты, файлы, голосовые сообщения, аудио- и видеозвонки — в одном приложении Fenyvo.',
      downloadAndroidArrow: '↓ Скачать для Android',
      downloadWindowsArrow: '↓ Скачать для Windows',
      viewFeatures: 'Посмотреть возможности',
      hashesPublished: 'SHA-256 опубликованы',
      online: 'в сети',
      outgoingAudio: 'Исходящий аудиозвонок',
      callQuestion: 'Созвонимся в Fenyvo?',
      alreadyHere: 'Да, я уже здесь.',
      incomingVideo: 'Входящий видеозвонок',
      connected: 'Соединено',
      messagePlaceholder: 'Сообщение…',
      stableCalls: 'Стабильные звонки',
      wifiMobile: 'Wi‑Fi и мобильная сеть',
      yourTalks: 'Ваши разговоры',
      underControl: 'Под вашим контролем',
      featuresTitle: 'Всё нужное для живого общения',
      featuresDescription: 'Fenyvo объединяет переписку, медиа и звонки в цельном интерфейсе для Android и Windows.',
      privateGroupChats: 'Личные и групповые чаты',
      privateGroupChatsText: 'Сообщения, реакции, закрепления и удобная история общения.',
      audioVideoCalls: 'Аудио- и видеозвонки',
      audioVideoCallsText: 'Понятные статусы вызова, история звонков и восстановление после краткого обрыва.',
      filesMedia: 'Файлы и медиа',
      filesMediaText: 'Отправляйте фотографии, видео, документы и голосовые сообщения.',
      mobileNetworks: 'Мобильные сети',
      mobileNetworksText: 'WebRTC адаптирует медиапоток к доступной пропускной способности соединения.',
      signatureSounds: 'Фирменные сигналы',
      signatureSoundsText: 'Разные звуки ожидания, занятой линии и завершения разговора.',
      ownProfile: 'Свой профиль',
      ownProfileText: 'Аватар, имя пользователя и настройки интерфейса без перегруженных экранов.',
      myContactQr: 'Мой контакт и QR',
      myContactQrText: 'Поделитесь персональной ссылкой или QR-кодом через любое приложение.',
      contactLinkProfile: 'Ссылка сразу в профиль',
      contactLinkProfileText: 'Контактная ссылка открывает карточку пользователя в установленном Fenyvo.',
      supportAssistant: 'Помощник поддержки',
      supportAssistantText: 'Ответы на вопросы о Fenyvo без автоматической передачи личных переписок.',
      differentKicker: 'Не как у всех',
      differentTitle: 'Функции, ради которых стоит попробовать Fenyvo',
      differentIntro: 'Не декоративные обещания, а уже работающие возможности публичной версии.',
      pulseAttractionText: 'Сообщите, когда готовы поговорить. Звонок начнётся после взаимной готовности — без навязчивого дозвона.',
      contactWithoutPhone: 'Контакт без номера телефона',
      contactWithoutPhoneText: 'Передайте QR-код или ссылку. После установки Fenyvo она откроет нужную карточку пользователя.',
      groupLive: 'Групповой эфир с ведущим',
      groupLiveText: 'До четырёх видеопотоков, разные раскладки, модераторы и управление участниками.',
      callsInContext: 'Звонки остаются в контексте',
      callsInContextText: 'Входящие, исходящие, пропущенные вызовы и длительность разговора отображаются прямо в чате.',
      soundSystem: 'Фирменная звуковая система',
      soundSystemText: 'Отдельные сигналы ожидания, занятой линии, завершения и сброса разговора.',
      helpWithoutChats: 'Помощь без чтения переписки',
      helpWithoutChatsText: 'Помощник отвечает на вопросы о Fenyvo, не получая ваши личные чаты автоматически.',
      groupChat: 'ГРУППОВОЙ ЧАТ',
      fourParticipants: '4 участника',
      teamSameWave: 'Команда на одной волне',
      groupChatText: 'Сообщения, файлы, голосовые записи и групповой созвон остаются в одном пространстве.',
      participantA: 'Участник A',
      meetingAtSix: 'Встречаемся в 18:00?',
      meetingPlan: 'План встречи.pdf',
      you: 'Вы',
      onTime: 'Да, буду вовремя.',
      participantC: 'Участник C',
      groupAudioLabel: 'Групповой аудиозвонок',
      groupVideoLabel: 'Групповой видеозвонок',
      realInterface: 'Настоящий интерфейс',
      interfaceTitle: 'Узнаваемый Fenyvo на каждом экране',
      interfaceDescription: 'Демонстрация основана на рабочем мобильном приложении, но не содержит имён, сообщений и аватаров реальных пользователей.',
      connection: '● связь',
      commandDeckText: 'Контакты, чаты и сохранённые сообщения собраны в одном спокойном пространстве.',
      searchContacts: '⌕   Поиск контактов и чатов',
      overview: 'ОБЗОР',
      people: 'ЛЮДИ',
      teams: 'КОМАНДЫ',
      fenyvoContact: 'Контакт Fenyvo',
      ready: 'готов',
      pulseTitle: 'Созвон без дозвона',
      pulseText: 'Сообщите о готовности поговорить. Вызов начнётся только после взаимного согласия.',
      audio: '☎ АУДИО',
      video: '▣ ВИДЕО',
      minutes15: '15 минут',
      hour1: '✓ 1 час',
      hours4: '4 часа',
      callHistory: 'ИСТОРИЯ ЗВОНКОВ',
      locally: 'локально',
      visibleInChat: 'Всё видно в чате',
      callHistoryText: 'Входящие и исходящие аудио- и видеозвонки отображаются рядом с сообщениями.',
      declined: 'Отклонён',
      noAnswer: 'Нет ответа',
      verifiedBuild: 'Проверяемая сборка',
      verifiedBuildText: 'Для опубликованного APK доступна контрольная сумма SHA‑256. Она позволяет убедиться, что файл не был изменён после публикации.',
      noPhoneBinding: 'Без привязки к номеру телефона',
      noPhoneBindingText: 'Для общения используется учётная запись Fenyvo.',
      apkChecksum: 'Контрольная сумма APK',
      apkChecksumText: 'Хеш опубликован на странице и отдельным текстовым файлом.',
      secureConnection: 'Защищённое соединение',
      secureConnectionText: 'Публичный клиент подключается к серверу через WSS/HTTPS.',
      downloadsKicker: 'Fenyvo в цифрах',
      downloadsTitle: 'Скачивания приложения',
      downloadsIntro: 'Отдельный открытый счётчик для каждой платформы.',
      downloadsNote: 'Считаются начатые скачивания с момента запуска счётчика.',
      androidDownloads: 'Android · скачиваний начато',
      windowsDownloads: 'Windows · скачиваний начато',
      iosPreparing: 'iPhone · версия готовится',
      installFenyvo: 'Установите Fenyvo',
      installText: 'Для Android доступен подписанный APK ARM64, для Windows — полный x64-комплект в ZIP-архиве.',
      androidPackage: '↓ Android APK · 77,5 МБ',
      windowsPackage: '↓ Windows ZIP · 31,4 МБ',
      downloadOnly: 'Скачивайте приложение только с fenyvo.com.',
      androidInstall: 'На Android разрешите браузеру установку APK из этого источника.',
      windowsInstall: 'На Windows распакуйте ZIP полностью и запустите',
      version: 'Версия',
      copy: 'Копировать',
      downloadAndroidHash: 'Скачать SHA‑256 Android',
      downloadWindowsHash: 'Скачать SHA‑256 Windows',
      privacy: 'Конфиденциальность',
      terms: 'Условия',
      rules: 'Правила',
      support: 'Поддержка',
      beforeDownload: 'Перед загрузкой Fenyvo',
      legalIntro: 'Приложение предназначено для пользователей от 16 лет. Вы отвечаете за отправляемый контент и обязуетесь использовать Fenyvo законно.',
      acceptPrefix: 'Я принимаю',
      termsOfUse: 'Условия использования',
      privacyAcknowledgement: 'и подтверждаю ознакомление с',
      privacyPolicy: 'Политикой конфиденциальности',
      ageConfirm: 'Мне исполнилось 16 лет.',
      cancel: 'Отмена',
      acceptDownload: 'Принять и скачать',
      copied: 'Скопировано',
      copyPrompt: 'Скопируйте SHA‑256:',
      shareFenyvo: '↗ Поделиться Fenyvo',
      shareText: 'Fenyvo — бесплатный мессенджер для Android и Windows: чаты, звонки и групповые эфиры.',
      shareCopied: 'Ссылка на Fenyvo скопирована',
      sharePrompt: 'Скопируйте ссылку на Fenyvo:',
      contactTitle: '@{username} — контакт Fenyvo'
    },
    uk: {
      galleryKicker: 'FENYVO 1.8.2+4251',
      galleryTitle: 'FENYVO у дії',
      galleryIntro: 'Справжні знімки екрана застосунку для Android і Windows. Натисніть зображення, щоб відкрити його у більшому розмірі.',
      galleryNote: 'Реальні екрани застосунку з демонстраційними іменами.',
      galleryAndroidLogin: 'Вхід',
      galleryAndroidPassword: 'Пароль',
      galleryAndroidConfirm: 'Підтвердження пароля',
      galleryAndroidMatch: 'Паролі збігаються',
      galleryAndroidScroll: 'Реєстрація з прокручуванням',
      galleryWindowsLogin: 'Вхід у Windows',
      galleryWindowsRegistration: 'Реєстрація у Windows',

      auto: 'Як на пристрої', languageCaption: 'Мова:', languageLabel: 'Мова сайту', homeLabel: 'Fenyvo — на головну', navLabel: 'Основна навігація', interfaceLabel: 'Приклад інтерфейсу Fenyvo',
      pageTitle: 'Fenyvo — приватне спілкування без зайвого', pageDescription: 'Fenyvo — месенджер для особистих і групових чатів, файлів, голосових та відеодзвінків. Завантажити для Android і Windows.', ogTitle: 'Fenyvo — месенджер', ogDescription: 'Спілкуйтеся, надсилайте файли та здійснюйте голосові й відеодзвінки.',
      features: 'Можливості', interface: 'Інтерфейс', security: 'Безпека', download: 'Завантажити', sharedContact: 'З вами поділилися контактом', contactHelp: 'Якщо Fenyvo вже встановлено, відкрийте картку користувача. Якщо застосунку немає — встановіть його, поверніться на цю сторінку та знову натисніть «Відкрити контакт».', openContact: 'Відкрити контакт у Fenyvo', downloadAndroid: 'Завантажити для Android',
      publicVersion: 'Тестова версія 1.8.2 · Android 4251 · Windows 4251', heroLeadA: 'Спілкування без', heroLeadB: 'зайвого шуму', heroDescription: 'Особисті та групові чати, файли, голосові повідомлення, аудіо- й відеодзвінки — в одному застосунку Fenyvo.', downloadAndroidArrow: '↓ Завантажити для Android', downloadWindowsArrow: '↓ Завантажити для Windows', viewFeatures: 'Переглянути можливості', hashesPublished: 'SHA-256 опубліковано',
      online: 'у мережі', outgoingAudio: 'Вихідний аудіодзвінок', callQuestion: 'Зідзвонимося у Fenyvo?', alreadyHere: 'Так, я вже тут.', incomingVideo: 'Вхідний відеодзвінок', connected: 'З’єднано', messagePlaceholder: 'Повідомлення…', stableCalls: 'Стабільні дзвінки', wifiMobile: 'Wi‑Fi і мобільна мережа', yourTalks: 'Ваші розмови', underControl: 'Під вашим контролем',
      featuresTitle: 'Усе потрібне для живого спілкування', featuresDescription: 'Fenyvo об’єднує листування, медіа та дзвінки в цілісному інтерфейсі для Android і Windows.', privateGroupChats: 'Особисті та групові чати', privateGroupChatsText: 'Повідомлення, реакції, закріплення та зручна історія спілкування.', audioVideoCalls: 'Аудіо- та відеодзвінки', audioVideoCallsText: 'Зрозумілі статуси виклику, історія дзвінків і відновлення після короткого розриву.', filesMedia: 'Файли й медіа', filesMediaText: 'Надсилайте фотографії, відео, документи та голосові повідомлення.', mobileNetworks: 'Мобільні мережі', mobileNetworksText: 'WebRTC адаптує медіапотік до доступної пропускної здатності з’єднання.', signatureSounds: 'Фірмові сигнали', signatureSoundsText: 'Різні звуки очікування, зайнятої лінії та завершення розмови.', ownProfile: 'Власний профіль', ownProfileText: 'Аватар, ім’я користувача та налаштування інтерфейсу без перевантажених екранів.',
      myContactQr: 'Мій контакт і QR', myContactQrText: 'Поділіться персональним посиланням або QR-кодом через будь-який застосунок.', contactLinkProfile: 'Посилання одразу в профіль', contactLinkProfileText: 'Контактне посилання відкриває картку користувача у встановленому Fenyvo.', supportAssistant: 'Помічник підтримки', supportAssistantText: 'Відповіді на запитання про Fenyvo без автоматичної передачі особистих листувань.',
      differentKicker: 'Не як у всіх', differentTitle: 'Функції, заради яких варто спробувати Fenyvo', differentIntro: 'Не декоративні обіцянки, а вже робочі можливості публічної версії.', pulseAttractionText: 'Повідомте, коли готові поговорити. Дзвінок почнеться після взаємної готовності — без нав’язливого додзвону.', contactWithoutPhone: 'Контакт без номера телефону', contactWithoutPhoneText: 'Передайте QR-код або посилання. Після встановлення Fenyvo воно відкриє потрібну картку користувача.', groupLive: 'Груповий ефір із ведучим', groupLiveText: 'До чотирьох відеопотоків, різні розкладки, модератори та керування учасниками.', callsInContext: 'Дзвінки залишаються в контексті', callsInContextText: 'Вхідні, вихідні, пропущені виклики та тривалість розмови відображаються прямо в чаті.', soundSystem: 'Фірмова звукова система', soundSystemText: 'Окремі сигнали очікування, зайнятої лінії, завершення та скидання розмови.', helpWithoutChats: 'Допомога без читання листування', helpWithoutChatsText: 'Помічник відповідає на запитання про Fenyvo, не отримуючи ваші особисті чати автоматично.',
      groupChat: 'ГРУПОВИЙ ЧАТ', fourParticipants: '4 учасники', teamSameWave: 'Команда на одній хвилі', groupChatText: 'Повідомлення, файли, голосові записи та груповий дзвінок залишаються в одному просторі.', participantA: 'Учасник A', meetingAtSix: 'Зустрічаємося о 18:00?', meetingPlan: 'План зустрічі.pdf', you: 'Ви', onTime: 'Так, буду вчасно.', participantC: 'Учасник C', groupAudioLabel: 'Груповий аудіодзвінок', groupVideoLabel: 'Груповий відеодзвінок',
      realInterface: 'Справжній інтерфейс', interfaceTitle: 'Упізнаваний Fenyvo на кожному екрані', interfaceDescription: 'Демонстрація базується на робочому мобільному застосунку, але не містить імен, повідомлень та аватарів реальних користувачів.', connection: '● зв’язок', commandDeckText: 'Контакти, чати та збережені повідомлення зібрані в одному спокійному просторі.', searchContacts: '⌕   Пошук контактів і чатів', overview: 'ОГЛЯД', people: 'ЛЮДИ', teams: 'КОМАНДИ', fenyvoContact: 'Контакт Fenyvo', ready: 'готово', pulseTitle: 'Розмова без додзвону', pulseText: 'Повідомте про готовність поговорити. Виклик почнеться лише після взаємної згоди.', audio: '☎ АУДІО', video: '▣ ВІДЕО', minutes15: '15 хвилин', hour1: '✓ 1 година', hours4: '4 години', callHistory: 'ІСТОРІЯ ДЗВІНКІВ', locally: 'локально', visibleInChat: 'Усе видно в чаті', callHistoryText: 'Вхідні та вихідні аудіо- й відеодзвінки відображаються поруч із повідомленнями.', declined: 'Відхилено', noAnswer: 'Немає відповіді',
      verifiedBuild: 'Перевірювана збірка', verifiedBuildText: 'Для опублікованого APK доступна контрольна сума SHA‑256. Вона дає змогу переконатися, що файл не змінювали після публікації.', noPhoneBinding: 'Без прив’язки до номера телефону', noPhoneBindingText: 'Для спілкування використовується обліковий запис Fenyvo.', apkChecksum: 'Контрольна сума APK', apkChecksumText: 'Хеш опубліковано на сторінці та окремим текстовим файлом.', secureConnection: 'Захищене з’єднання', secureConnectionText: 'Публічний клієнт підключається до сервера через WSS/HTTPS.', downloadsKicker: 'Fenyvo у цифрах', downloadsTitle: 'Завантаження застосунку', downloadsIntro: 'Окремий відкритий лічильник для кожної платформи.', downloadsNote: 'Рахуються розпочаті завантаження з моменту запуску лічильника.', androidDownloads: 'Android · завантажень розпочато', windowsDownloads: 'Windows · завантажень розпочато', iosPreparing: 'iPhone · версія готується',
      installFenyvo: 'Установіть Fenyvo', installText: 'Для Android доступний підписаний APK ARM64, для Windows — повний x64-комплект у ZIP-архіві.', androidPackage: '↓ Android APK · 77,5 МБ', windowsPackage: '↓ Windows ZIP · 31,4 МБ', downloadOnly: 'Завантажуйте застосунок лише з fenyvo.com.', androidInstall: 'На Android дозвольте браузеру встановлення APK із цього джерела.', windowsInstall: 'На Windows повністю розпакуйте ZIP і запустіть', version: 'Версія', copy: 'Копіювати', downloadAndroidHash: 'Завантажити SHA‑256 Android', downloadWindowsHash: 'Завантажити SHA‑256 Windows',
      privacy: 'Конфіденційність', terms: 'Умови', rules: 'Правила', support: 'Підтримка', beforeDownload: 'Перед завантаженням Fenyvo', legalIntro: 'Застосунок призначений для користувачів віком від 16 років. Ви відповідаєте за надісланий контент і зобов’язуєтеся використовувати Fenyvo законно.', acceptPrefix: 'Я приймаю', termsOfUse: 'Умови використання', privacyAcknowledgement: 'і підтверджую ознайомлення з', privacyPolicy: 'Політикою конфіденційності', ageConfirm: 'Мені виповнилося 16 років.', cancel: 'Скасувати', acceptDownload: 'Прийняти та завантажити', copied: 'Скопійовано', copyPrompt: 'Скопіюйте SHA‑256:', shareFenyvo: '↗ Поділитися Fenyvo', shareText: 'Fenyvo — безкоштовний месенджер для Android і Windows: чати, дзвінки та групові ефіри.', shareCopied: 'Посилання на Fenyvo скопійовано', sharePrompt: 'Скопіюйте посилання на Fenyvo:', contactTitle: '@{username} — контакт Fenyvo'
    },
    en: {
      galleryKicker: 'FENYVO 1.8.2+4251',
      galleryTitle: 'FENYVO in action',
      galleryIntro: 'Real screenshots of the Android and Windows apps. Select an image to view it at full size.',
      galleryNote: 'Real application screens with sample usernames.',
      galleryAndroidLogin: 'Sign in',
      galleryAndroidPassword: 'Password',
      galleryAndroidConfirm: 'Confirm password',
      galleryAndroidMatch: 'Passwords match',
      galleryAndroidScroll: 'Registration scrolled',
      galleryWindowsLogin: 'Windows sign in',
      galleryWindowsRegistration: 'Windows registration',

      auto: 'Use device language', languageCaption: 'Language:', languageLabel: 'Website language', homeLabel: 'Fenyvo — home', navLabel: 'Main navigation', interfaceLabel: 'Fenyvo interface preview',
      pageTitle: 'Fenyvo — private communication without the noise', pageDescription: 'Fenyvo is a messenger for private and group chats, files, voice messages, audio calls and video calls. Download for Android and Windows.', ogTitle: 'Fenyvo — messenger', ogDescription: 'Chat, share files, and make voice and video calls.',
      features: 'Features', interface: 'Interface', security: 'Security', download: 'Download', sharedContact: 'Someone shared a contact with you', contactHelp: 'If Fenyvo is already installed, open the user profile. Otherwise install the app, return to this page, and select “Open contact” again.', openContact: 'Open contact in Fenyvo', downloadAndroid: 'Download for Android',
      publicVersion: 'Test release 1.8.2 · Android 4251 · Windows 4251', heroLeadA: 'Communication without', heroLeadB: 'the extra noise', heroDescription: 'Private and group chats, files, voice messages, audio calls and video calls — all in one Fenyvo app.', downloadAndroidArrow: '↓ Download for Android', downloadWindowsArrow: '↓ Download for Windows', viewFeatures: 'Explore features', hashesPublished: 'SHA-256 published',
      online: 'online', outgoingAudio: 'Outgoing audio call', callQuestion: 'Want to talk on Fenyvo?', alreadyHere: 'Yes, I’m already here.', incomingVideo: 'Incoming video call', connected: 'Connected', messagePlaceholder: 'Message…', stableCalls: 'Stable calls', wifiMobile: 'Wi‑Fi and mobile networks', yourTalks: 'Your conversations', underControl: 'Under your control',
      featuresTitle: 'Everything you need for real conversations', featuresDescription: 'Fenyvo brings messages, media and calls together in one coherent interface for Android and Windows.', privateGroupChats: 'Private and group chats', privateGroupChatsText: 'Messages, reactions, pinned items and a clear conversation history.', audioVideoCalls: 'Audio and video calls', audioVideoCallsText: 'Clear call states, call history and recovery after a brief connection loss.', filesMedia: 'Files and media', filesMediaText: 'Send photos, videos, documents and voice messages.', mobileNetworks: 'Mobile networks', mobileNetworksText: 'WebRTC adapts the media stream to the available connection bandwidth.', signatureSounds: 'Signature sounds', signatureSoundsText: 'Different tones for ringing, a busy line and the end of a call.', ownProfile: 'Your profile', ownProfileText: 'Avatar, username and interface settings without cluttered screens.',
      myContactQr: 'My contact and QR', myContactQrText: 'Share your personal link or QR code through any app.', contactLinkProfile: 'A link straight to the profile', contactLinkProfileText: 'A contact link opens the user profile in the installed Fenyvo app.', supportAssistant: 'Support assistant', supportAssistantText: 'Get answers about Fenyvo without automatically sharing private conversations.',
      differentKicker: 'Beyond the usual', differentTitle: 'Features that make Fenyvo worth trying', differentIntro: 'Not decorative promises — working features already available in the public release.', pulseAttractionText: 'Share when you are ready to talk. A call starts after mutual availability, without repeated ringing.', contactWithoutPhone: 'Connect without a phone number', contactWithoutPhoneText: 'Share a QR code or link. After Fenyvo is installed, it opens the intended user profile.', groupLive: 'Hosted group live sessions', groupLiveText: 'Up to four video streams, multiple layouts, moderators and participant controls.', callsInContext: 'Calls remain in context', callsInContextText: 'Incoming, outgoing and missed calls, plus call duration, appear directly in the chat.', soundSystem: 'A signature sound system', soundSystemText: 'Distinct sounds for ringing, a busy line, call completion and hang-up.', helpWithoutChats: 'Help without reading your chats', helpWithoutChatsText: 'The assistant answers questions about Fenyvo without automatically receiving your private conversations.',
      groupChat: 'GROUP CHAT', fourParticipants: '4 participants', teamSameWave: 'A team on the same wavelength', groupChatText: 'Messages, files, voice notes and a group call stay in one space.', participantA: 'Participant A', meetingAtSix: 'Meet at 18:00?', meetingPlan: 'Meeting plan.pdf', you: 'You', onTime: 'Yes, I’ll be on time.', participantC: 'Participant C', groupAudioLabel: 'Group audio call', groupVideoLabel: 'Group video call',
      realInterface: 'Real interface', interfaceTitle: 'A recognizable Fenyvo experience on every screen', interfaceDescription: 'This demonstration is based on the working mobile app and contains no names, messages or avatars from real users.', connection: '● connected', commandDeckText: 'Contacts, chats and saved messages live in one calm workspace.', searchContacts: '⌕   Search contacts and chats', overview: 'OVERVIEW', people: 'PEOPLE', teams: 'TEAMS', fenyvoContact: 'Fenyvo contact', ready: 'ready', pulseTitle: 'Plan a call without ringing', pulseText: 'Let someone know you are ready to talk. The call starts only after both people agree.', audio: '☎ AUDIO', video: '▣ VIDEO', minutes15: '15 minutes', hour1: '✓ 1 hour', hours4: '4 hours', callHistory: 'CALL HISTORY', locally: 'local', visibleInChat: 'Calls stay visible in chat', callHistoryText: 'Incoming and outgoing audio and video calls appear alongside messages.', declined: 'Declined', noAnswer: 'No answer',
      verifiedBuild: 'Verifiable build', verifiedBuildText: 'A SHA‑256 checksum is provided for the published APK so you can verify that the file has not changed since publication.', noPhoneBinding: 'No phone-number requirement', noPhoneBindingText: 'Communication uses your Fenyvo account.', apkChecksum: 'APK checksum', apkChecksumText: 'The hash is published on this page and as a separate text file.', secureConnection: 'Secure connection', secureConnectionText: 'The public client connects to the server using WSS/HTTPS.', downloadsKicker: 'Fenyvo in numbers', downloadsTitle: 'App downloads', downloadsIntro: 'A separate public counter for every platform.', downloadsNote: 'Counts downloads started since the counter was launched.', androidDownloads: 'Android · downloads started', windowsDownloads: 'Windows · downloads started', iosPreparing: 'iPhone · version in development',
      installFenyvo: 'Install Fenyvo', installText: 'Android includes a signed ARM64 APK; Windows includes the complete x64 package in a ZIP archive.', androidPackage: '↓ Android APK · 77.5 MB', windowsPackage: '↓ Windows ZIP · 31.4 MB', downloadOnly: 'Download the app only from fenyvo.com.', androidInstall: 'On Android, allow your browser to install the APK from this source.', windowsInstall: 'On Windows, fully extract the ZIP and launch', version: 'Version', copy: 'Copy', downloadAndroidHash: 'Download Android SHA‑256', downloadWindowsHash: 'Download Windows SHA‑256',
      privacy: 'Privacy', terms: 'Terms', rules: 'Acceptable use', support: 'Support', beforeDownload: 'Before downloading Fenyvo', legalIntro: 'The app is intended for users aged 16 and over. You are responsible for the content you send and agree to use Fenyvo lawfully.', acceptPrefix: 'I accept the', termsOfUse: 'Terms of Use', privacyAcknowledgement: 'and acknowledge the', privacyPolicy: 'Privacy Policy', ageConfirm: 'I am at least 16 years old.', cancel: 'Cancel', acceptDownload: 'Accept and download', copied: 'Copied', copyPrompt: 'Copy the SHA‑256:', shareFenyvo: '↗ Share Fenyvo', shareText: 'Fenyvo is a free messenger for Android and Windows with chats, calls, and hosted group live sessions.', shareCopied: 'Fenyvo link copied', sharePrompt: 'Copy the Fenyvo link:', contactTitle: '@{username} — Fenyvo contact'
    }
  };

  const sourceToKey = Object.create(null);
  Object.keys(messages.ru).forEach(function (key) {
    sourceToKey[messages.ru[key]] = key;
  });

  const boundTextNodes = [];
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let node;
  while ((node = walker.nextNode())) {
    const parent = node.parentElement;
    if (!parent || /^(SCRIPT|STYLE|CODE)$/i.test(parent.tagName)) continue;
    const original = node.nodeValue.trim();
    const key = sourceToKey[original];
    if (!key) continue;
    boundTextNodes.push({ node: node, key: key });
  }

  function savedPreference() {
    try {
      const saved = localStorage.getItem(storageKey);
      return saved === 'auto' || supported.includes(saved) ? saved : 'auto';
    } catch (_) {
      return 'auto';
    }
  }

  function detectedLanguage() {
    const languages = Array.isArray(navigator.languages) && navigator.languages.length
      ? navigator.languages
      : [navigator.language || 'en'];
    for (const language of languages) {
      const base = String(language).toLowerCase().split('-')[0];
      if (supported.includes(base)) return base;
    }
    return 'en';
  }

  function resolveLanguage(preference) {
    return preference === 'auto' ? detectedLanguage() : preference;
  }

  let currentLanguage = resolveLanguage(savedPreference());

  function t(key) {
    return (messages[currentLanguage] && messages[currentLanguage][key]) || messages.en[key] || messages.ru[key] || key;
  }

  function setMeta(selector, value) {
    const element = document.querySelector(selector);
    if (element) element.setAttribute('content', value);
  }

  function applyLanguage(preference) {
    currentLanguage = resolveLanguage(preference);
    document.documentElement.lang = currentLanguage;
    const contactName = document.getElementById('contact-name');
    const contactInvite = document.getElementById('contact-invite');
    document.title = contactName && contactInvite && !contactInvite.hidden && contactName.textContent.trim()
      ? t('contactTitle').replace('{username}', contactName.textContent.trim().replace(/^@/, ''))
      : t('pageTitle');
    setMeta('meta[name="description"]', t('pageDescription'));
    setMeta('meta[property="og:title"]', t('ogTitle'));
    setMeta('meta[property="og:description"]', t('ogDescription'));

    boundTextNodes.forEach(function (binding) {
      const raw = binding.node.nodeValue;
      const leading = (raw.match(/^\s*/) || [''])[0];
      const trailing = (raw.match(/\s*$/) || [''])[0];
      binding.node.nodeValue = leading + t(binding.key) + trailing;
    });

    const brand = document.querySelector('.brand');
    const navigation = document.querySelector('.navlinks');
    const preview = document.querySelector('.phone-wrap');
    const selector = document.getElementById('language-select');
    if (brand) brand.setAttribute('aria-label', t('homeLabel'));
    if (navigation) navigation.setAttribute('aria-label', t('navLabel'));
    if (preview) preview.setAttribute('aria-label', t('interfaceLabel'));
    const groupAudio = document.getElementById('group-audio-action');
    const groupVideo = document.getElementById('group-video-action');
    if (groupAudio) groupAudio.setAttribute('aria-label', t('groupAudioLabel'));
    if (groupVideo) groupVideo.setAttribute('aria-label', t('groupVideoLabel'));
    if (selector) {
      selector.setAttribute('aria-label', t('languageLabel'));
      selector.value = preference;
    }
    window.dispatchEvent(new CustomEvent('fenyvo:languagechange', { detail: { language: currentLanguage, preference: preference } }));
  }

  const selector = document.getElementById('language-select');
  const initialPreference = savedPreference();
  if (selector) {
    selector.addEventListener('change', function () {
      const preference = selector.value;
      try { localStorage.setItem(storageKey, preference); } catch (_) {}
      applyLanguage(preference);
    });
  }

  window.fenyvoI18n = {
    t: t,
    apply: applyLanguage,
    language: function () { return currentLanguage; },
    contactTitle: function (username) { return t('contactTitle').replace('{username}', username); }
  };

  applyLanguage(initialPreference);
})();
