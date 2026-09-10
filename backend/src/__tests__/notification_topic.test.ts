/**
 * Les notifications par sujet partent réellement.
 *
 * Relevé en production : 109 échecs, zéro succès. Aucune notification par
 * sujet n'était jamais partie depuis la mise en service.
 *
 *     [FCM] Erreur topic: Messaging payload contains an invalid "android"
 *     property. Valid properties are "data" and "notification".
 *
 * La cause : `messaging().sendToTopic()` est l'ancienne API. Elle n'accepte
 * qu'un `MessagingPayload` — `notification` et `data`, rien d'autre. Le code
 * lui passait aussi `android` (canal, priorité, son) et `apns`, qui
 * n'appartiennent qu'à l'API moderne `send()`.
 *
 * Ce qui rendait la panne muette : l'exception est attrapée, journalisée, et
 * l'appelant reçoit `{ success: false }`. Rien ne remonte à l'écran, rien ne
 * distingue « envoyé » de « jamais parti » — sauf à lire le journal du serveur.
 *
 * Ce ne sont pas des envois secondaires : les rappels avant match et les
 * notifications de résultat passent tous par là. C'est aussi ce que le site
 * annonce désormais — « prévenu au coup d'envoi, prévenu au résultat ».
 */

// Prisma importerait le `.env` du projet pour y trouver DATABASE_URL. Ce test
// ne touche pas la base : on le coupe net plutôt que de laisser fuiter des
// variables de production dans une suite qui croit être isolée.
jest.mock('../lib/prisma', () => ({ prisma: {} }));

const envoyes: any[] = [];
const ancienneApi = jest.fn();

jest.mock('firebase-admin', () => ({
  __esModule: true,
  default: {
    apps: [{}], // déjà initialisé : initializeApp n'est pas appelé
    messaging: () => ({
      send: (message: any) => { envoyes.push(message); return Promise.resolve('msg-id'); },
      sendToTopic: (...args: any[]) => { ancienneApi(...args); return Promise.resolve({}); },
    }),
  },
}));

describe('notifications par sujet', () => {
  beforeAll(() => {
    // getAdmin() rend `null` sans ces variables, et le service bascule alors en
    // mode console : le test passerait sans avoir rien éprouvé.
    process.env.FIREBASE_PROJECT_ID  = 'test';
    process.env.FIREBASE_PRIVATE_KEY = 'test';
  });

  beforeEach(() => { envoyes.length = 0; ancienneApi.mockClear(); });

  it('utilise send({ topic }) et non l\'ancienne sendToTopic', async () => {
    const { NotificationService } = await import('../services/notification.service');
    const svc = new NotificationService();

    const r: any = await svc.sendToTopic('match_updates', {
      title: 'Coup d\'envoi', body: 'Real Madrid vs Barcelone',
    });

    expect(ancienneApi).not.toHaveBeenCalled();
    expect(envoyes).toHaveLength(1);
    expect(envoyes[0].topic).toBe('match_updates');
    expect(r.success).toBe(true);
  });

  it('transporte bien le canal Android et le réglage iOS', async () => {
    // C'est précisément ce que l'ancienne API refusait. Un envoi qui aurait
    // « marché » en les laissant tomber ne serait pas une correction : la
    // notification arriverait sans son ni canal, donc silencieuse sur Android 8+.
    const { NotificationService } = await import('../services/notification.service');
    await new NotificationService().sendToTopic('match_updates', {
      title: 'Résultat', body: '2 - 1',
    });

    const msg = envoyes[0];
    expect(msg.android?.notification?.channelId).toBe('pronowin_high');
    expect(msg.android?.priority).toBe('high');
    expect(msg.apns?.payload?.aps?.sound).toBe('default');
  });

  it('une erreur d\'envoi ne passe pas pour un succès', async () => {
    // La panne était muette parce que l'exception était avalée. Le contrat
    // reste « on n'explose pas », mais `success` doit dire la vérité.
    jest.resetModules();
    jest.doMock('firebase-admin', () => ({
      __esModule: true,
      default: {
        apps: [{}],
        messaging: () => ({ send: () => Promise.reject(new Error('refus FCM')) }),
      },
    }));

    const { NotificationService } = await import('../services/notification.service');
    const r: any = await new NotificationService().sendToTopic('match_updates', {
      title: 'x', body: 'y',
    });

    expect(r.success).toBe(false);
    expect(r.error).toContain('refus FCM');
  });
});
