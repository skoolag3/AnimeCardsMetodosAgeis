import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import {
  BadRequestException,
  ValidationError,
  ValidationPipe,
} from '@nestjs/common';
import { HttpExceptionFilter } from './common/filters/http-exception.filter';
import { AppModule } from './core/app/app.module';
import helmet from 'helmet';
import type { NextFunction, Request, Response } from 'express';
import { collectDefaultMetrics, Counter, Histogram, Registry } from 'prom-client';

type ValidationErrorDetail = {
  field: string;
  messages: string[];
};

function getAllowedOrigins(): string[] {
  return (
    process.env.FRONTEND_URLS ??
    process.env.FRONTEND_URL ??
    'http://localhost:3000'
  )
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
}

function formatValidationErrors(
  errors: ValidationError[],
): ValidationErrorDetail[] {
  return errors.flatMap((error) => {
    const messages = Object.values(error.constraints ?? {});
    const children = error.children?.length
      ? formatValidationErrors(error.children).map((child) => ({
          ...child,
          field: `${error.property}.${child.field}`,
        }))
      : [];

    return [
      ...(messages.length
        ? [
            {
              field: error.property,
              messages,
            },
          ]
        : []),
      ...children,
    ];
  });
}

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { rawBody: true });
  const allowedOrigins = getAllowedOrigins();

  app.use(
    helmet({
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'none'"],
          frameAncestors: ["'none'"],
        },
      },
    }),
  );
  const expressApp = app.getHttpAdapter().getInstance();
  const metricas = new Registry();
  collectDefaultMetrics({ register: metricas, prefix: 'animecards_' });
  const requisicoes = new Counter({
    name: 'animecards_http_requests_total',
    help: 'Total de requisicoes HTTP',
    labelNames: ['method', 'route', 'status'] as const,
    registers: [metricas],
  });
  const duracao = new Histogram({
    name: 'animecards_http_request_duration_seconds',
    help: 'Duracao das requisicoes HTTP em segundos',
    labelNames: ['method', 'route', 'status'] as const,
    buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
    registers: [metricas],
  });
  expressApp.get('/metrics', async (_req: Request, res: Response) => {
    res.set('Content-Type', metricas.contentType);
    res.end(await metricas.metrics());
  });
  expressApp.get('/health', (_req: Request, res: Response) => res.json({ status: 'ok' }));
  expressApp.use((req: Request, res: Response, next: NextFunction) => {
    if (req.path === '/metrics' || req.path === '/health') return next();
    const inicio = process.hrtime.bigint();
    res.on('finish', () => {
      const labels = {
        method: req.method,
        route: req.route?.path ?? 'unmatched',
        status: String(res.statusCode),
      };
      requisicoes.inc(labels);
      duracao.observe(labels, Number(process.hrtime.bigint() - inicio) / 1e9);
    });
    next();
  });
  expressApp.disable('x-powered-by');
  expressApp.set('trust proxy', 1);
  app.useGlobalFilters(new HttpExceptionFilter());
  app.enableCors({
    origin(
      origin: string | undefined,
      callback: (err: Error | null, allow?: boolean) => void,
    ) {
      if (!origin || allowedOrigins.includes(origin)) {
        callback(null, true);
        return;
      }

      callback(null, false);
    },
    credentials: true,
  });
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      exceptionFactory: (errors) =>
        new BadRequestException({
          message: 'Dados invalidos.',
          details: formatValidationErrors(errors),
        }),
    }),
  );
  await app.listen(process.env.PORT ?? 3001);
}
void bootstrap();
