export async function publishToLiveSessions(
  fetcher: typeof fetch, base: string, service: string, topic: string, payload: Record<string, unknown>,
): Promise<boolean> {
    // Private channel policies are cached at join. Bind each destination to a
    // live Auth session and re-evaluate recipients for every publication.
    const recipients = await fetcher(base + '/rest/v1/rpc/fr13_live_topics', {
      method: 'POST', headers: {apikey: service, Authorization: 'Bearer ' + service, 'Content-Type': 'application/json'},
      body: JSON.stringify({p_sender_topic: topic}), signal: AbortSignal.timeout(5000),
    });
    if (!recipients.ok) return false;
    const topics: unknown = await recipients.json();
    if (!Array.isArray(topics) || !topics.length || !topics.every(t => typeof t === 'string' && t.startsWith('fr13:'))) return false;
    for (let offset = 0; offset < topics.length; offset += 10) {
      const response = await fetcher(base + '/realtime/v1/api/broadcast', {
      method: 'POST', headers: {apikey: service, Authorization: 'Bearer ' + service, 'Content-Type': 'application/json'},
      body: JSON.stringify({messages: topics.slice(offset, offset + 10).map(destination => ({topic: destination, event: 'location', payload, private: true}))}),
      signal: AbortSignal.timeout(5000),
      });
      if (!response.ok) return false;
    }
    return true;
  }
