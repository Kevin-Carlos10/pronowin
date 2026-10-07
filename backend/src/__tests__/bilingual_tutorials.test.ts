jest.mock('../lib/prisma', () => ({prisma: {
 tutorial:{findMany:jest.fn(),findUnique:jest.fn(),update:jest.fn().mockResolvedValue({})},
 user:{findUnique:jest.fn()},tutorialProgress:{findMany:jest.fn().mockResolvedValue([]),findUnique:jest.fn().mockResolvedValue(null)}
}}));
import {prisma} from '../lib/prisma';
import {TutorialService} from '../services/tutorial.service';
const p=prisma as any;
const article={id:'t',title:'Titre',titleEn:'Title',description:'Résumé',descriptionEn:'Summary',isPremium:true,articleContent:'SECRET FR',articleContentEn:'SECRET EN',videoUrl:'https://example.test/private.mp4'};
beforeEach(()=>{jest.clearAllMocks();p.tutorial.findMany.mockResolvedValue([article]);p.tutorial.findUnique.mockResolvedValue(article);});
it.each([undefined,'free','expired'])('restricts premium tutorial bodies in both languages for %s',async(kind)=>{
 p.user.findUnique.mockResolvedValue({subscriptionPlan:kind==='expired'?'premium':'free',subscriptionExpiresAt:new Date(Date.now()-1000)});
 const svc=new TutorialService();
 for(const row of [...await svc.getAll({userId:kind}),await svc.getOne('t',kind)]){
  expect(row.title_en).toBe('Title');expect(row.locked).toBe(true);expect(row.article_content).toBeNull();expect(row.article_content_en).toBeNull();expect(row.video_url).toBeNull();
 }
});
it('serves both full translations to a current subscriber',async()=>{
 p.user.findUnique.mockResolvedValue({subscriptionPlan:'premium',subscriptionExpiresAt:new Date(Date.now()+86400000)});
 const svc=new TutorialService();
 for(const row of [...await svc.getAll({userId:'premium'}),await svc.getOne('t','premium')]){
  expect(row.locked).toBe(false);expect(row.article_content).toBe('SECRET FR');expect(row.article_content_en).toBe('SECRET EN');
 }
});
it('keeps free content accessible to guests',async()=>{
 p.tutorial.findUnique.mockResolvedValue({...article,isPremium:false});
 expect((await new TutorialService().getOne('t')).article_content_en).toBe('SECRET EN');
 expect(p.user.findUnique).not.toHaveBeenCalled();
});
