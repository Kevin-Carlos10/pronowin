const mockSent: any[] = [];
const mockArchived: any[] = [];
const mockUsers = [{id:'one', notificationPrefs: null, appareils:[{jeton:'fr-token',language:'fr'},{jeton:'en-token',language:'en'}]}];
jest.mock('../lib/prisma', () => ({prisma:{
 user:{findUnique:jest.fn(async()=>mockUsers[0]),findMany:jest.fn(async()=>mockUsers)},
 notification:{create:jest.fn(async(q:any)=>{mockArchived.push(q.data);return q.data}),createMany:jest.fn(async(q:any)=>mockArchived.push(...q.data))},
 appareilNotification:{deleteMany:jest.fn(async()=>({count:0}))}
}}));
jest.mock('firebase-admin',()=>({__esModule:true,default:{apps:[{}],messaging:()=>({
 send:async(m:any)=>{mockSent.push(m);return 'ok'},
 sendEachForMulticast:async(m:any)=>{mockSent.push(m);return {responses:m.tokens.map(()=>({success:true})),successCount:m.tokens.length,failureCount:0}}
})}}));
import {NotificationService} from '../services/notification.service';
import {englishPair, optionalText} from '../i18n/editorial';
import {bilingual, translatedNotificationText} from '../i18n/notifications';
import {prisma} from '../lib/prisma';
const svc=new NotificationService();
beforeAll(()=>{process.env.FIREBASE_PROJECT_ID='test';process.env.FIREBASE_PRIVATE_KEY='test'});
beforeEach(()=>{mockSent.length=0;mockArchived.length=0; (prisma.user.findUnique as jest.Mock).mockResolvedValue(mockUsers[0]);});
test('personal notifications use each device language and a single bilingual archive',async()=>{
 await svc.sendToUser('one',{title:'Premium activé !',body:'Accès Premium actif pour 30 jours. Profitez des pronostics VIP !'},'premium');
 expect(mockSent).toHaveLength(2);
 expect(mockSent.find(m=>m.tokens[0]==='en-token').notification.title).toBe('Premium activated!');
 expect(mockSent.find(m=>m.tokens[0]==='fr-token').notification.title).toBe('Premium activé !');
 expect(mockArchived).toHaveLength(1);expect(mockArchived[0].titleEn).toBe('Premium activated!');
});
test('opt out preserves the bilingual inbox but sends nothing',async()=>{
 (prisma.user.findUnique as jest.Mock).mockResolvedValue({...mockUsers[0],notificationPrefs:{premium:false}});
 const r=await svc.sendToUser('one',{title:'Premium activé !',body:'Message'},'premium');
 expect(r.success).toBe(false);expect(mockSent).toHaveLength(0);expect(mockArchived).toHaveLength(1);
});
test('campaign splits tokens by language, counts people once and keeps deep links',async()=>{
 const r=await svc.sendToSegment('all',{title:'Bonjour',body:'Texte français',titleEn:'Hello',bodyEn:'English text',deepLink:'/compte'});
 expect(r.sent).toBe(1);expect(mockSent).toHaveLength(2);
 expect(mockSent[1].notification.body).toBe('English text');expect(mockSent[1].data.deep_link).toBe('/compte');
 expect(mockArchived[0].bodyEn).toBe('English text');
});
test('public VIP pushes never reveal either editorial language',async()=>{
 await svc.notifyPronosticPublished({homeTeam:'Netherlands',awayTeam:'Belgium',pronosticId:'p',predictionLabel:'SECRET FR',predictionLabelEn:'SECRET EN',isPremium:true});
 expect(mockSent.map(m=>m.topic)).toEqual(['match_alerts','match_alerts_en']);
 expect(JSON.stringify(mockSent)).not.toContain('SECRET');
 expect(mockSent[1].notification.body).toBe('Netherlands vs Belgium — VIP prediction available');
});
test('an authored translation takes precedence, unknown prose remains intact',()=>{
 expect(bilingual({title:'Bonjour',body:'Texte',titleEn:'Hello',bodyEn:'Text'}).bodyEn).toBe('Text');
 expect(translatedNotificationText('Commentaire libre')).toBe('Commentaire libre');
});
test('validation rejects partial/oversized translations; blank clears and absent preserves',()=>{
 expect(()=>englishPair('Title','')).toThrow();expect(()=>englishPair('a'.repeat(101),'Text')).toThrow();
 expect(optionalText('')).toBeNull();expect(optionalText(undefined)).toBeUndefined();
 expect(()=>optionalText({html:'x'})).toThrow();
});
