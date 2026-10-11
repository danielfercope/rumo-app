-- Coluna geoespacial de companies. Como latitude/longitude agora são
-- double precision NOT NULL (sem dado legado sujo pra tolerar), dá pra usar
-- uma GENERATED COLUMN em vez do trigger de cast seguro da versão anterior.

ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS geom geography(Point, 4326)
  GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography) STORED;

CREATE INDEX IF NOT EXISTS companies_geom_gist ON public.companies USING GIST (geom);
