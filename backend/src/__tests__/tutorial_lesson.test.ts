import {parseLesson} from '../utils/tutorial_lesson';
test('preserves PATCH omission, clears explicitly, sorts chapters',()=>{
 expect(parseLesson(undefined)).toBeUndefined();
 expect(parseLesson(null)).toEqual({fr:{},en:{}});
 expect(parseLesson({fr:{chapters:[{title:'B',seconds:60},{title:'A',seconds:0}]}}).fr.chapters[0].title).toBe('A');
});
test.each([[], 'bad', {fr:[]}, {fr:{quiz:[null]}}, {fr:{chapters:[null]}},
 {fr:{quiz:[{question:'Q',options:['A',''],answer:0,explanation:'E'}]}},
 {fr:{quiz:[{question:'Q',options:['A','B'],answer:2,explanation:'E'}]}},
 {en:{objectives:Array(7).fill('x')}}, {fr:{chapters:[{title:'A',seconds:-1}]}}])('rejects malformed learning data %p', value=>expect(()=>parseLesson(value)).toThrow());
test('keeps both authored languages',()=>{
 const quiz={question:'Q',options:['A','B'],answer:1,explanation:'Because B'};
 expect(parseLesson(JSON.stringify({en:{quiz:[quiz]},fr:{objectives:['Lire']}}))).toMatchObject({en:{quiz:[quiz]},fr:{objectives:['Lire']}});
});
