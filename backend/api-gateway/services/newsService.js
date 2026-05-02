import axios from 'axios';

const getNews = async (origin, destination) => {
  try {
    // SIMPLE & EFFECTIVE QUERY
    const query = `${origin} ${destination} transport`;

    const response = await axios.get(
      'https://newsapi.org/v2/everything',
      {
        params: {
          q: query,
          apiKey: process.env.NEWS_API_KEY,
          pageSize: 10,
          sortBy: 'publishedAt',
          language: 'en'
        }
      }
    );

    const articles = response.data.articles || [];



    const isRecent = (date) => {
      const hours = (Date.now() - new Date(date)) / (1000 * 60 * 60);
      return hours < 72;
    };

    const keywords = [
      'traffic',
      'road',
      'transport',
      'logistics',
      'delay',
      'strike',
      'accident',
      'closure',
      'weather'
    ];

    // LIGHT FILTER
    const filtered = articles.filter(article => {
      const title = (article.title || '').toLowerCase();

      const hasLocation =
        title.includes(origin.toLowerCase()) ||
        title.includes(destination.toLowerCase());

      const hasKeyword = keywords.some(k => title.includes(k));

      return isRecent(article.publishedAt) && hasLocation && hasKeyword;
    });
    
    let finalArticles = filtered;

    if (finalArticles.length === 0) {
      finalArticles = articles.filter(article => {
        const title = article.title.toLowerCase();
        return keywords.some(k => title.includes(k));
      });
    }

    // Final fallback (never empty)
    if (!finalArticles || finalArticles.length === 0) {
      return [
        {
          title: "No major logistics disruptions reported on this route",
          source: "System",
          publishedAt: new Date().toISOString()
        }
      ];
    }

    return finalArticles.slice(0, 3).map(article => ({
      title: article.title || "Unknown Article",
      source: article.source?.name || "Unknown Source",
      publishedAt: article.publishedAt
    }));

  } catch (error) {
    console.error('News API Error:', error.message);

    return [
      {
        title: 'No major disruptions reported',
        source: 'System',
        publishedAt: new Date().toISOString()
      }
    ];
  }
};

export default { getNews };