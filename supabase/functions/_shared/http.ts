export const jsonHeaders = { "content-type": "application/json; charset=utf-8" };

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

export function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

export async function authenticatedUser(request: Request): Promise<{ id: string; token: string }> {
  const authorization = request.headers.get("authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (!token) throw new Response(JSON.stringify({ error: "Authentication required" }), { status: 401, headers: jsonHeaders });

  const url = requiredEnvironment("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ?? requiredEnvironment("SUPABASE_PUBLISHABLE_KEY");
  const response = await fetch(`${url}/auth/v1/user`, {
    headers: { apikey: publishableKey, authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw new Response(JSON.stringify({ error: "Invalid session" }), { status: 401, headers: jsonHeaders });
  const user = await response.json();
  return { id: user.id, token };
}

