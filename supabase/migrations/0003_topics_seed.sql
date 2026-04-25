-- Seed an initial topic catalogue. Idempotent: re-runs are safe.
-- The slug is the stable identifier; localised display names live in
-- name_en / name_ja / name_zh.

insert into public.topics (slug, name_en, name_ja, name_zh) values
  ('music',         'Music',           '音楽',       '音樂'),
  ('movies',        'Movies & TV',     '映画とTV',   '電影與電視'),
  ('books',         'Books',           '本',         '書籍'),
  ('travel',        'Travel',          '旅行',       '旅行'),
  ('food',          'Food',            '食べ物',     '美食'),
  ('coffee',        'Coffee',          'コーヒー',   '咖啡'),
  ('fitness',       'Fitness',         'フィットネス','健身'),
  ('gaming',        'Gaming',          'ゲーム',     '遊戲'),
  ('tech',          'Tech',            'テック',     '科技'),
  ('art',           'Art',             'アート',     '藝術'),
  ('photography',   'Photography',     '写真',       '攝影'),
  ('startups',      'Startups',        'スタートアップ','創業'),
  ('design',        'Design',          'デザイン',   '設計'),
  ('languages',     'Languages',       '言語',       '語言'),
  ('night-owls',    'Night owls',      '夜更かし',   '夜貓族'),
  ('mental-health', 'Mental health',   'メンタルヘルス','身心健康'),
  ('philosophy',    'Philosophy',      '哲学',       '哲學'),
  ('outdoors',      'Outdoors',        'アウトドア', '戶外'),
  ('pets',          'Pets',            'ペット',     '寵物'),
  ('music-making',  'Making music',    '音楽制作',   '音樂創作')
on conflict (slug) do nothing;
