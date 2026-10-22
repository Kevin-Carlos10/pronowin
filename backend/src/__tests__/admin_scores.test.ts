jest.mock('../lib/prisma', () => ({prisma:{match:{findMany:jest.fn()}}}));
import {prisma} from '../lib/prisma';
import {getAdminScores} from '../controllers/admin_scores.controller';

const response = () => { const r:any={status:jest.fn(),json:jest.fn(),setHeader:jest.fn()}; r.status.mockReturnValue(r); return r; };
describe('lecture groupée des scores admin',()=>{
  beforeEach(()=>jest.clearAllMocks());
  it('ne lit que les matchs demandés et les champs de direct',async()=>{
    (prisma.match.findMany as jest.Mock).mockResolvedValue([{id:'m1',status:'LIVE',homeScore:0,awayScore:0,elapsedMinutes:3,pronostic:null}]);
    const res=response(); await getAdminScores({body:{ids:['m1','m1']}} as any,res);
    expect(prisma.match.findMany).toHaveBeenCalledWith({where:{id:{in:['m1']}},select:{id:true,status:true,homeScore:true,awayScore:true,elapsedMinutes:true,pronostic:{select:{result:true}}}});
    expect(res.json.mock.calls[0][0].matches[0].homeScore).toBe(0);
    expect(res.setHeader).toHaveBeenCalledWith('Cache-Control','no-store');
  });
  it.each([null,[],['../x'],[{}],Array(401).fill('m1')])('refuse une liste invalide',async ids=>{
    const res=response(); await getAdminScores({body:{ids}} as any,res);
    expect(res.status).toHaveBeenCalledWith(400); expect(prisma.match.findMany).not.toHaveBeenCalled();
  });
  it('signale une panne au lieu de retourner une liste vide',async()=>{
    (prisma.match.findMany as jest.Mock).mockRejectedValue(Error('database'));
    const res=response(); await getAdminScores({body:{ids:['m1']}} as any,res);
    expect(res.status).toHaveBeenCalledWith(503);
  });
});
