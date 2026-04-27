import { NextResponse } from 'next/dist/server/web/spec-extension/response';
import type { NextRequest } from 'next/dist/server/web/spec-extension/request';

export function proxy(request: NextRequest) {
  const session = request.cookies.get('session');

  // If user is trying to access the login page while already authenticated, redirect to dashboard
  if (request.nextUrl.pathname.startsWith('/login')) {
    if (session) {
      return NextResponse.redirect(new URL('/', request.url));
    }
    return NextResponse.next();
  }

  // Protect all other routes
  if (!session) {
    return NextResponse.redirect(new URL('/login', request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico).*)'],
};
