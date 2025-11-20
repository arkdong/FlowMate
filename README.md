# FlowMate
AI Personal Assistant powered by GreenPT

### Problem Definition
In the modern era, people have many fragmented bits of free time that is not efficently used. For example, 30 minutes between a lecture and a bus ride. In addition, we are overloaded my the information and entertainment that exists on the Internet. Like recommended YouTube videos, Message from a friend, or even email. This time could be productive or meaningful rather than just mindlessly surfing on the internet. 

### Solution
FlowMate caputers application usage with App name, context, and durations. User can start a Fucus Session to be focus on certain topic or just general topic. The session keeps track of the what user was doing based on the context and the app, and give summery after the focus session.  This way it helps user to be more focues into their goal

In addition, FlowMate keep track of whether the user is distracteed.
- If there is a goal for the Focus Session, then for any application usage that is longer than 5 minutes, the context and the goal will be send to GreenPT to check whether this context align with the goal. If not then a notification will be pushed to the user.
- If there is no goal set up by the user, then for any application usage longer than 5 minutes, the context of the current application to gether with all previous recordings will be send to GreenPT. It decide whether this context align with 80% of the topic coverd in the previous recordings. If not then a notification will be pushed to the user.

FlowMate also have the ability to choose between different GreenPT model and reasoning level, this determine the input length, output length, and the quality of the AI summery. For the purpose of sustainability, the energy usage and CO2 emission inidcator will be shown, that update based on GreenPT usage. 


